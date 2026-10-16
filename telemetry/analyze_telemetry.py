#!/usr/bin/env python3
"""Preprocess raw Claude API telemetry captures into aggregated, LLM-friendly artifacts.

Input: a raw capture directory, `~/.client-1-telemetry/api-bodies/<session-uuid>/`
— a folder of paired `<uuid>.request.json` / `req_<id>.response.json` files,
i.e. every Claude API call (full request body + full response body) made
during one Claude Code invocation. Called with no argument, the script picks
the most recent capture under that root. Zip archives are still accepted as
an argument, but they are no longer the native form: filesystem timestamps
are finer-grained than a zip's, so latencies and gaps come out truer.

Give each run a `--label` — model/effort/thinking are read straight out of
each request body (authoritative), so the label carries only what the bodies
cannot say: which command was invoked, on which host.

Output: one `analysis_YYYYMMDD<letter>/` directory of flat CSVs — small,
aggregated artifacts sized for a downstream LLM to reason over directly,
instead of ~1GB of raw nested JSON. With no `--out`, the next free letter for
today is used. Written reports live in `reports/`, not here.

Why this is harder than "just zip open + json.load": the capture format has
no explicit request<->response join key (request files are named by a local
capture uuid, response files by the API's own request id — different
namespaces, never equal). Two links ARE reliable and are what this script
leans on:
  1. `request.diagnostics.previous_message_id` == the *previous* response's
     `id` in the same conversation. This is exact and is used to reconstruct
     conversation chains (turn order, chain roots, retries).
  2. Wall-clock order: within one archive, requests and responses are
     produced by a live HTTP round trip, so sorting all events by mtime and
     doing FIFO (oldest pending request <-> next response) pairs each
     request with its own response correctly except during heavy
     concurrency (parallel subagents), where it's a good approximation, not
     exact. This is used only for latency numbers; conversation structure
     comes from (1), which is exact.

Since Claude Code 2.1.301 (capture of 2026-10-15) the host uses server-side
threads: a request carries `thread: {type: create|continue}` and a `continue`
sends only the DELTA since the previous turn (2 messages for 90k billed
tokens). FIFO pairing then mixes parallel subagents badly enough to corrupt
chains, and first-message keying no longer sees the conversation. On such
captures pairing switches to token prediction (`match_calls_by_tokens`) and a
`continue` inherits its conversation from its chain predecessor
(`resolve_conversations`).
"""
import csv
import hashlib
import json
import re
import statistics
import sys
import zipfile
from collections import defaultdict, deque
from datetime import datetime
from pathlib import Path

TELEMETRY_DIR = Path(__file__).parent
CAPTURE_ROOT = Path.home() / ".client-1-telemetry" / "api-bodies"
OUT_DIR = None  # résolu dans main() : analysis_YYYYMMDD<lettre>

LONG_GAP_THRESHOLD_S = 60
RETRY_WINDOW_S = 180
PHASE_TOOLS = {"Skill", "Agent", "Task"}
# Les horodatages viennent des entrées de zip, dont le format ne stocke que des
# secondes paires : une chaîne fille peut donc paraître démarrer jusqu'à deux
# secondes AVANT la délégation qui la lance. La tolérance absorbe cet artefact
# sans ouvrir la porte à un appariement lointain.
SPAWN_TOLERANCE_S = 5

# Le bandeau de facturation que l'hote colle en tete du system prompt. Son
# `cc_version` porte un suffixe par DEFINITION d'agent (orchestrateur, chaque
# type de sous-agent, chaque fork de skill) et `cc_is_subagent` separe
# l'orchestrateur du reste. Mesure du 07/09/2026 : 8 suffixes distincts sur une
# capture de 2 206 appels, la ou deviner d'apres le texte du prompt echoue.
BILLING_HEADER_RE = re.compile(r"x-anthropic-billing-header:\s*([^\n]*)")
SYSTEM_REMINDER_RE = re.compile(r"<system-reminder>.*?</system-reminder>", re.S)
# Le corps d'un fork (`context: fork`) EST le SKILL.md, et commence donc par sa
# ligne de base. Un sous-agent qui s'est fait precharger le meme skill la cite
# plus loin, apres son propre prompt de delegation — d'ou l'ancrage en tete.
SKILL_BASEDIR_RE = re.compile(r"\ABase directory for this skill:\s*\S*?/skills/([\w-]+)")
# Les forks du harnais (ligne de statut, suggestion de prompt, résumé d'absence)
# reprennent l'historique COMPLET d'un agent et se chaînent sur sa dernière
# réponse : sans ce tri, ils gonflent la conversation de l'agent qu'ils résument.
# Reconnus à la consigne finale que l'hôte leur colle — textes de l'hôte, à
# revérifier quand une capture montre un agent anormalement gros.
HARNESS_FORK_MARKERS = (
    ("agent_summary", "Bad (too long)"),                    # depuis 2.1.301
    ("agent_summary", "Describe your most recent action"),  # avant 2.1.301
    ("prompt_suggestion", "Reply with ONLY the suggestion"),
    ("away_summary", "Lead with the overall goal"),
)
# Jetons par caractère de JSON, pour prédire la taille facturée d'une requête
# (appariement par jetons). Mesuré le 16/10/2026 : 1 213 continues sur 1 354 à
# moins de 5 % d'écart.
CHARS_PER_TOKEN = 3.2
MAX_CONTINUE_ERR = 0.5
IMAGE_TOKENS = 1600


def zip_mtime(info: zipfile.ZipInfo) -> float:
    return datetime(*info.date_time).timestamp()


def content_chars(content) -> int:
    if isinstance(content, str):
        return len(content)
    total = 0
    if isinstance(content, list):
        for block in content:
            if not isinstance(block, dict):
                continue
            t = block.get("type")
            if t == "text":
                total += len(block.get("text", "") or "")
            elif t == "tool_result":
                c = block.get("content")
                if isinstance(c, str):
                    total += len(c)
                elif isinstance(c, list):
                    for b2 in c:
                        if isinstance(b2, dict) and b2.get("type") == "text":
                            total += len(b2.get("text", "") or "")
            elif t == "tool_use":
                total += len(json.dumps(block.get("input", {})))
    return total


def message_text(content) -> str:
    """Le texte brut d'un message, blocs `text` concaténés."""
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "".join(
            b.get("text", "") or ""
            for b in content
            if isinstance(b, dict) and b.get("type") == "text"
        )
    return ""


def has_tool_result(content) -> bool:
    return isinstance(content, list) and any(
        isinstance(b, dict) and b.get("type") == "tool_result" for b in content
    )


def system_text(system) -> str:
    if isinstance(system, str):
        return system
    if isinstance(system, list):
        return "\n".join(b.get("text", "") or "" for b in system if isinstance(b, dict))
    return ""


def prev_request_id(system_txt: str) -> str:
    """`cc_prev_req` du bandeau : l'identifiant de requete de l'appel PRECEDENT
    du meme fil — et les fichiers de reponse sont nommes par cet identifiant
    (`req_<id>.response.json`). C'est donc une jointure requete<->reponse EXACTE,
    la seule de la capture, et elle survit a la concurrence.
    """
    m = BILLING_HEADER_RE.search(system_txt)
    if not m:
        return ""
    v = re.search(r"cc_prev_req=([^\s;]+)", m.group(1))
    return v.group(1) if v else ""


def actor_signature(system_txt: str):
    """(suffixe de definition d'agent, est-ce un sous-agent) lu dans le bandeau.

    Substitut n. 2 de §M.17.5. Le suffixe de `cc_version` change avec la
    DEFINITION de l'agent, pas avec sa version : deux sous-agents de types
    differents ne le partagent jamais, deux instances du meme type si.
    """
    m = BILLING_HEADER_RE.search(system_txt)
    if not m:
        return "", False
    header = m.group(1)
    ver = re.search(r"cc_version=([^\s;]+)", header)
    sub = re.search(r"cc_is_subagent=true", header)
    return (ver.group(1).rsplit(".", 1)[-1] if ver else ""), bool(sub)


def conversation_signature(messages) -> str:
    """Empreinte du premier tour ASSISTANT — identite de conversation de secours.

    `previous_message_id` est exact quand il est la, mais il manque : sur la
    capture du 07/09/2026 il rend 411 racines pour 2 206 appels, dont 358
    tombent EN PLEIN MILIEU d'une conversation (n_messages >> 2). Le premier
    tour assistant, lui, est immuable une fois produit — contrairement a
    `messages[0]`, que l'hote re-injecte et mute (system-reminders). Meme
    capture : 50 conversations, aucun appel perdu.

    Piege verifie : `messages[1]` est un message de role `system` identique
    partout (la liste des skills) — le hasher fusionne tout le run en une seule
    chaine. Il faut le premier `role == assistant`, et rien d'autre.

    Limite connue : deux forks du meme skill lances sur la meme portee peuvent
    partager leur premier tour et fusionner. Le cout par ACTEUR reste exact
    (chaque appel porte son propre bandeau) ; seul le COMPTE de conversations
    de ce type est alors un plancher. Recouper avec les invocations `Skill`
    des parents.
    """
    first_assistant = next((m for m in messages if m.get("role") == "assistant"), None)
    if first_assistant is None:
        return ""
    return hashlib.sha1(_signature_text(first_assistant.get("content")).encode()).hexdigest()[:12]


def _signature_text(content) -> str:
    if isinstance(content, str):
        return content
    parts = []
    for b in content or []:
        if not isinstance(b, dict):
            continue
        t = b.get("type")
        if t == "text":
            parts.append("T:" + (b.get("text") or ""))
        elif t == "thinking":
            parts.append("K:" + (b.get("thinking") or "")[:400])
        elif t == "tool_use":
            parts.append("U:" + str(b.get("name")) + json.dumps(b.get("input", {}), sort_keys=True)[:400])
    return "\n".join(parts)


def payload_chars(obj) -> int:
    """Longueur JSON d'un corps, une image comptée à son coût forfaitaire.

    Une capture d'écran Playwright pèse des centaines de Ko de base64 pour
    ~1 600 jetons : comptée en caractères, elle fait prédire 300 k à une
    requête d'évaluateur qui en facture 60 k.
    """
    if isinstance(obj, dict):
        if obj.get("type") == "image":
            return int(IMAGE_TOKENS * CHARS_PER_TOKEN)
        return sum(len(k) + 4 + payload_chars(v) for k, v in obj.items())
    if isinstance(obj, list):
        return sum(payload_chars(v) + 1 for v in obj)
    if isinstance(obj, str):
        return len(obj) + 2
    return len(json.dumps(obj))


def harness_fork_kind(content) -> str:
    text = message_text(content)
    return next((kind for kind, marker in HARNESS_FORK_MARKERS if marker in text), "")


def extract_request(name: str, mtime: float, data: dict) -> dict:
    diag = data.get("diagnostics") or {}
    thread = data.get("thread") or {}
    meta = data.get("metadata") or {}
    try:
        user_id = json.loads(meta.get("user_id", "{}"))
    except (json.JSONDecodeError, TypeError):
        user_id = {}
    sys_txt = system_text(data.get("system"))
    system_chars = len(sys_txt)
    actor_sig, is_subagent = actor_signature(sys_txt)
    messages = data.get("messages") or []
    first_user = next((m for m in messages if m.get("role") == "user"), None)
    task_text = SYSTEM_REMINDER_RE.sub("", message_text(first_user.get("content")) if first_user else "").strip()
    skill_fork = SKILL_BASEDIR_RE.search(task_text)
    last_msg = messages[-1] if messages else {}
    first_msg = messages[0] if messages else {}
    betas = data.get("betas") or []
    return {
        "file": name,
        "mtime": mtime,
        "session_id": user_id.get("session_id"),
        "prev_id": thread.get("previous_message_id") or diag.get("previous_message_id"),
        # `create` | `continue` | "" (requête hors thread, historique complet).
        "thread_type": thread.get("type") or "",
        "messages_chars": payload_chars(messages),
        "tools_chars": len(json.dumps(data.get("tools") or [])),
        "harness_fork": harness_fork_kind(last_msg.get("content")) if messages else "",
        "model": data.get("model"),
        "effort": (data.get("output_config") or {}).get("effort"),
        "thinking_type": (data.get("thinking") or {}).get("type"),
        "n_messages": len(messages),
        "n_tools_declared": len(data.get("tools") or []),
        "system_chars": system_chars,
        "last_msg_role": last_msg.get("role"),
        "last_msg_chars": content_chars(last_msg.get("content")),
        "last_msg_is_tool_result": has_tool_result(last_msg.get("content")),
        # Le premier message d'une conversation ne grandit pas avec elle : pour un
        # sous-agent, c'est le prompt que le parent lui a passé, précédé du
        # system-reminder. C'est la seule clé de rattachement parent -> sous-agent
        # disponible (voir label_chains).
        "first_msg_text": message_text(first_msg.get("content")),
        # Reconstruction de conversation sans `previous_message_id` (§M.17.5).
        "conv_sig": conversation_signature(messages),
        "prev_req_id": prev_request_id(sys_txt),
        "actor_sig": actor_sig,
        "is_subagent": is_subagent,
        "actor_kind": (
            f"fork:{skill_fork.group(1)}" if skill_fork
            else ("subagent" if is_subagent else "orchestrator")
        ),
        "task_text": task_text,
        "n_betas": len(betas),
        "has_1m_context_beta": any("context-1m" in b for b in betas),
    }


def extract_response(name: str, mtime: float, data: dict) -> dict:
    usage = data.get("usage") or {}
    content = data.get("content") or []
    tool_names = [b.get("name") for b in content if isinstance(b, dict) and b.get("type") == "tool_use"]
    text_chars = sum(len(b.get("text", "") or "") for b in content if isinstance(b, dict) and b.get("type") == "text")
    thinking_chars = sum(
        len(b.get("thinking", "") or "") for b in content if isinstance(b, dict) and b.get("type") == "thinking"
    )
    skill_calls = [
        b.get("input", {}).get("skill")
        for b in content
        if isinstance(b, dict) and b.get("type") == "tool_use" and b.get("name") == "Skill"
    ]
    agent_calls = [
        b.get("input", {}).get("description")
        for b in content
        if isinstance(b, dict) and b.get("type") == "tool_use" and b.get("name") in ("Agent", "Task")
    ]
    # Le prompt intégral de chaque délégation. C'est lui qui permet de rattacher
    # la chaîne du sous-agent à l'appel qui l'a lancé : Claude Code le repose tel
    # quel dans le premier message de la conversation fille.
    delegations = [
        {
            "prompt": (b.get("input") or {}).get("prompt") or "",
            "description": (b.get("input") or {}).get("description") or "",
            "subagent_type": (b.get("input") or {}).get("subagent_type") or "",
        }
        for b in content
        if isinstance(b, dict) and b.get("type") == "tool_use" and b.get("name") in ("Agent", "Task")
    ]
    return {
        "file": name,
        "req_id": name[:-len(".response.json")] if name.endswith(".response.json") else name,
        "id": data.get("id"),
        "mtime": mtime,
        "model": data.get("model"),
        "stop_reason": data.get("stop_reason"),
        "input_tokens": usage.get("input_tokens", 0) or 0,
        "cache_read_tokens": usage.get("cache_read_input_tokens", 0) or 0,
        "cache_creation_tokens": usage.get("cache_creation_input_tokens", 0) or 0,
        "output_tokens": usage.get("output_tokens", 0) or 0,
        "thinking_tokens": (usage.get("output_tokens_details") or {}).get("thinking_tokens", 0) or 0,
        "n_tool_use_blocks": len(tool_names),
        "tool_names": ";".join(t for t in tool_names if t),
        "text_chars": text_chars,
        "thinking_chars": thinking_chars,
        "skill_calls": ";".join(s for s in skill_calls if s),
        "agent_calls": ";".join(a for a in agent_calls if a),
        "delegations": [d for d in delegations if d["prompt"]],
    }


def load_archive(path: Path):
    """Charge une archive .zip OU un repertoire de capture brute.

    Le repertoire est la forme native de la capture (`~/.client-1-telemetry/
    api-bodies/<session-uuid>/`) ; le .zip n'en est qu'un emballage. Les deux
    donnent les memes champs, a une nuance pres : les horodatages de zip sont
    arrondis a la seconde paire, ceux du systeme de fichiers sont au flottant.
    Plus fin est mieux — les latences et les ecarts n'en sont que plus justes.
    """
    requests, responses = [], []
    if path.is_dir():
        for f in sorted(path.rglob("*.json")):
            base = f.name
            if not (base.endswith(".request.json") or base.endswith(".response.json")):
                continue
            try:
                data = json.loads(f.read_text())
            except (json.JSONDecodeError, UnicodeDecodeError):
                continue
            mtime = f.stat().st_mtime
            if base.endswith(".request.json"):
                requests.append(extract_request(base, mtime, data))
            else:
                responses.append(extract_response(base, mtime, data))
        return requests, responses
    with zipfile.ZipFile(path) as zf:
        for info in zf.infolist():
            name = info.filename
            if "__MACOSX" in name or info.is_dir():
                continue
            mtime = zip_mtime(info)
            base = name.rsplit("/", 1)[-1]
            try:
                data = json.loads(zf.read(info))
            except json.JSONDecodeError:
                continue
            if base.endswith(".request.json"):
                requests.append(extract_request(base, mtime, data))
            elif base.endswith(".response.json"):
                responses.append(extract_response(base, mtime, data))
    return requests, responses


LATENCY_SUSPECT_S = 600  # a single API call legitimately taking >10min is rare; flag rather than trust


def match_calls(requests, responses):
    """Pair each request with its own response via global FIFO-by-mtime.

    There is no explicit join key (request files are named by a local capture
    uuid, response files by the API's own request id — different namespaces).
    Within one archive, HTTP round trips make FIFO (oldest pending request <->
    next response) correct except across a failed/orphaned call, where it can
    misattribute one later response's latency. That risk is bounded and only
    affects `latency_s` (flagged via `latency_suspect` downstream) — chain
    structure and `gap_before_s` come from the exact previous_message_id link
    in link_chains() below and are unaffected by any mismatch here.

    Erreur bornee en mesure (capture du 07/09/2026, 2 206 appels) :
      - les jetons factures suivent de pres la TAILLE PROPRE de la requete
        (rapport facture/octets/3,7 : p10 1,27, mediane 1,33, p90 1,41) —
        48 appels seulement, soit 2,2 %, s'ecartent d'un facteur 2 ;
      - 3,6 % seulement du temps du run voit deux DEFINITIONS d'agent
        differentes en vol en meme temps, seule fenetre ou un echange entre
        acteurs est possible.
    Donc la ventilation du COUT par acteur tient a ~2 pres. Ce qui ne tient
    pas, c'est le champ cote reponse recopie sur le voisin : on a vu un
    `kairos-close` — qui n'a pas l'outil `Agent` — credite d'une delegation.
    Croiser un bloc `Agent`/`Skill` surprenant avec le corps de la requete du
    parent avant d'en conclure quoi que ce soit.

    Piste pour un appariement exact, verifiee a moitie : `cc_prev_req` du
    bandeau nomme le FICHIER de reponse de l'appel precedent du meme fil, et il
    concorde avec `previous_message_id` 1 796 fois sur 1 796, pour une
    couverture superieure (2 153 requetes contre 1 796). Il manque le dernier
    maillon — nommer la requete qui a PRODUIT cette reponse. Les deux essais
    faits echouent : regrouper par fil puis decaler d'un cran se casse des que
    deux forks du meme skill se melangent, et "les messages du predecesseur
    sont un prefixe de ceux du successeur" est faux (l'hote mute les messages
    entre deux tours : 252 correspondances sur 2 153).
    """
    events = [(r["mtime"], 0, "REQ", r) for r in requests] + [(r["mtime"], 1, "RES", r) for r in responses]
    events.sort(key=lambda e: (e[0], e[1]))
    pending = deque()
    calls = []
    orphan_responses = []
    for _, _, kind, rec in events:
        if kind == "REQ":
            pending.append(rec)
        else:
            if pending:
                calls.append({"request": pending.popleft(), "response": rec})
            else:
                orphan_responses.append(rec)
    orphan_requests = list(pending)
    return calls, orphan_requests, orphan_responses


def match_calls_by_tokens(requests, responses):
    """Appariement pour les captures en threads serveur (2.1.301+).

    Le FIFO y échoue : chaque générateur, évaluateur et gate tourne en
    parallèle d'un orchestrateur qui se réveille à chaque retour, et un seul
    échange contamine toute la chaîne en aval — mesuré le 16/10/2026, « une
    security review de 438 min », « un évaluateur qui lance 26 Agent ».

    Deux propriétés des threads remplacent l'ordre d'arrivée :

    - **la taille facturée est prévisible.** Une `continue` ne transporte que
      le delta : sa réponse facture ≈ facturé(réponse parente) + sortie
      (réponse parente) + delta / CHARS_PER_TOKEN. Une requête complète
      (`create` ou hors thread) facture ≈ (system + messages + outils)
      / CHARS_PER_TOKEN — plus grossier, mais elles sont rares ;
    - **l'identité d'agent est connue d'avance.** Une `continue` qui cite la
      réponse X porte le suffixe `cc_version` de son agent : la requête qui a
      PRODUIT X a forcément le même. C'est ce garde-fou qui supprime la
      contamination entre agents.

    Chaque réponse, dans l'ordre d'arrivée, prend parmi les requêtes en attente
    (antérieures, même modèle, même agent si connu) celle dont la prédiction
    est la plus proche. La réponse parente d'une `continue` est toujours
    arrivée avant elle, donc déjà appariée quand on en a besoin.

    Deux exclusions, chacune vue sur la capture du 16/10 :

    - une requête ne s'apparie jamais à la réponse qu'elle CITE : le fichier de
      réponse s'écrit parfois jusqu'à 20 s après que la requête suivante est
      partie, et sans ce garde on comptait 73 cycles de chaîne ;
    - une `continue` dont la prédiction est exacte (parent connu) refuse une
      réponse à plus de MAX_CONTINUE_ERR d'écart : la dernière réponse d'une
      conversation, citée par personne, n'a pas de garde d'agent, et un
      évaluateur à 60 k prenait une réponse d'orchestrateur à 350 k.

    `pair_err` (écart relatif prédiction/facturé) est posé sur chaque appel :
    au 16/10, 1 213 continues sur 1 354 à moins de 5 %.
    """
    need_agent = {r["prev_id"]: r["actor_sig"] for r in requests if r["thread_type"] == "continue" and r["prev_id"]}
    events = [(r["mtime"], 0, "REQ", r) for r in requests] + [(r["mtime"], 1, "RES", r) for r in responses]
    events.sort(key=lambda e: (e[0], e[1]))
    pending, calls, orphan_responses = [], [], []
    by_resp_id = {}

    def billed(res):
        return res["input_tokens"] + res["cache_read_tokens"] + res["cache_creation_tokens"]

    def predicted(req):
        """(prédiction, exacte ?) — exacte quand la réponse parente est connue."""
        parent = by_resp_id.get(req["prev_id"]) if req["thread_type"] == "continue" else None
        if parent is not None:
            return billed(parent) + parent["output_tokens"] + req["messages_chars"] / CHARS_PER_TOKEN, True
        return (req["system_chars"] + req["messages_chars"] + req["tools_chars"]) / CHARS_PER_TOKEN, False

    for mtime, _, kind, rec in events:
        if kind == "REQ":
            pending.append(rec)
            continue
        agent = need_agent.get(rec["id"])
        best = None
        for req in pending:
            if req["model"] != rec["model"] or (agent is not None and req["actor_sig"] != agent):
                continue
            if req["prev_id"] == rec["id"]:
                continue
            pred, exact = predicted(req)
            err = abs(billed(rec) - pred) / max(pred, 1)
            if exact and err > MAX_CONTINUE_ERR:
                continue
            # à écart égal, la requête la plus ancienne
            score = err + (mtime - req["mtime"]) / 1e6
            if best is None or score < best[0]:
                best = (score, req, err)
        if best is None:
            orphan_responses.append(rec)
            continue
        pending.remove(best[1])
        if rec["id"]:
            by_resp_id[rec["id"]] = rec
        calls.append({"request": best[1], "response": rec, "pair_err": best[2]})

    # Seconde passe : les deux exclusions ci-dessus laissent quelques réponses
    # sans requête (10 au 16/10), et chaque orpheline coupe une chaîne en deux.
    # On les apparie aux requêtes restantes antérieures, garde d'agent seule.
    leftovers = []
    for rec in orphan_responses:
        agent = need_agent.get(rec["id"])
        cands = [
            req for req in pending
            if req["mtime"] <= rec["mtime"] and req["model"] == rec["model"]
            and (agent is None or req["actor_sig"] == agent) and req["prev_id"] != rec["id"]
        ]
        if not cands:
            leftovers.append(rec)
            continue
        scored = [(abs(billed(rec) - predicted(r)[0]) / max(predicted(r)[0], 1), r) for r in cands]
        err, req = min(scored, key=lambda s: s[0])
        pending.remove(req)
        calls.append({"request": req, "response": rec, "pair_err": err})
    return calls, pending, leftovers


def link_chains(calls):
    """Exact chain reconstruction via previous_message_id -> response.id."""
    resp_id_to_call = {c["response"]["id"]: c for c in calls}
    # Deux reponses capturees peuvent porter le MEME id (retry rejoue, corps
    # recapture) : le dictionnaire ne garde alors que la derniere, et un
    # `prev_id` peut pointer vers un appel PLUS TARDIF que le sien — d'ou des
    # cycles dans `chain_prev`. Verifie le 10/10/2026 : turn_index() bouclait
    # sans fin sur un tel cycle et a gele la machine deux fois (45 Go + swap).
    n_dup_resp_ids = len(calls) - len(resp_id_to_call)
    for c in calls:
        prev_id = c["request"]["prev_id"]
        c["chain_prev"] = resp_id_to_call.get(prev_id) if prev_id else None

    # Briser les cycles AVANT toute traversee : un lien qui reboucle est coupe
    # (l'appel devient racine de chaine), et on le dit plutot que de geler.
    acyclic = set()
    n_cycles_cut = 0
    for c in calls:
        path, path_ids, cur = [], set(), c
        while cur is not None and id(cur) not in acyclic:
            if id(cur) in path_ids:
                cur["chain_prev"] = None
                n_cycles_cut += 1
                break
            path_ids.add(id(cur))
            path.append(cur)
            cur = cur["chain_prev"]
        acyclic.update(path_ids)
    if n_dup_resp_ids or n_cycles_cut:
        print(f"  warning: {n_dup_resp_ids} duplicated response id(s), {n_cycles_cut} chain_prev cycle(s) cut")

    turn_cache, root_cache = {}, {}

    def turn_index(c):
        chain, cur = [], c
        while cur is not None and id(cur) not in turn_cache:
            chain.append(cur)
            cur = cur["chain_prev"]
        base = turn_cache.get(id(cur), 0) if cur is not None else 0
        for i, node in enumerate(reversed(chain)):
            base += 1
            turn_cache[id(node)] = base
        return turn_cache[id(c)]

    def root_id(c):
        chain, cur = [], c
        while cur is not None and id(cur) not in root_cache:
            chain.append(cur)
            cur = cur["chain_prev"]
        root = root_cache.get(id(cur)) if cur is not None else chain[-1]["request"]["file"]
        for node in chain:
            root_cache[id(node)] = root
        return root

    for c in calls:
        c["turn_index"] = turn_index(c)
        c["chain_root"] = root_id(c)
        cp = c["chain_prev"]
        c["gap_before_s"] = (c["request"]["mtime"] - cp["response"]["mtime"]) if cp else None
        c["latency_s"] = max(0.0, c["response"]["mtime"] - c["request"]["mtime"])
        c["latency_suspect"] = c["latency_s"] > LATENCY_SUSPECT_S
    return calls


def label_chains(calls):
    """Rattache chaque chaîne de sous-agent à la délégation qui l'a lancée.

    Le problème : `chains.csv` identifiait ses lignes par un `chain_root` opaque
    (`4bb4a160-….request.json`, 5,7 M de tokens facturés) sans dire QUELLE
    délégation c'était. C'est la seule chose que l'étiquette OTLP `agent_name`
    donnait gratuitement — et elle a été retirée, à raison : sur ces mêmes runs
    elle ne prenait que 2 valeurs distinctes pour 16 délégations
    (`general-purpose` ×15), là où `description` les distingue toutes.

    La clé de rattachement : Claude Code repose le prompt de délégation TEL QUEL
    dans le premier message de la conversation fille, précédé d'un
    `<system-reminder>`. C'est donc une INCLUSION, jamais une égalité — vérifié
    le 30/08/2026 : l'égalité exacte apparie 0 chaîne sur 8, l'inclusion les
    apparie.

    Deux garde-fous, parce qu'une inclusion seule est ambiguë :

    - **appariement un-à-un** — une délégation prend au plus une chaîne, une
      chaîne reçoit au plus une délégation. Sans quoi un prompt court inclus
      dans un prompt long revendiquerait les deux ;
    - **la fille démarre APRÈS sa délégation** (à `SPAWN_TOLERANCE_S` près).
      C'est ce qui départage deux exécutions du même sous-agent avec le même
      prompt — le cas courant quand une story est retentée.

    Les délégations sont traitées dans l'ordre chronologique et prennent la
    chaîne candidate la plus précoce : deux lancements identiques s'apparient
    alors dans l'ordre où ils sont partis.

    Une chaîne non appariée garde une étiquette vide — c'est le cas normal de la
    conversation principale et des appels auxiliaires, qui ne sont les fils de
    personne.
    """
    for c in calls:
        c["chain_agent_description"] = ""
        c["chain_subagent_type"] = ""

    delegations = [
        dict(d, spawn_mtime=c["response"]["mtime"])
        for c in calls
        for d in (c["response"].get("delegations") or [])
    ]
    if not delegations:
        return calls

    premiers = {}
    for c in calls:
        root = c["chain_root"]
        if root not in premiers or c["turn_index"] < premiers[root]["turn_index"]:
            premiers[root] = c

    etiquettes = {}
    for d in sorted(delegations, key=lambda d: d["spawn_mtime"]):
        candidats = [
            (premier["request"]["mtime"], root)
            for root, premier in premiers.items()
            if root not in etiquettes
            and d["prompt"] in (premier["request"]["first_msg_text"] or "")
            and premier["request"]["mtime"] >= d["spawn_mtime"] - SPAWN_TOLERANCE_S
        ]
        if not candidats:
            continue
        _, retenu = min(candidats)
        etiquettes[retenu] = (d["description"], d["subagent_type"])

    for c in calls:
        if c["chain_root"] in etiquettes:
            c["chain_agent_description"], c["chain_subagent_type"] = etiquettes[c["chain_root"]]
    return calls


def resolve_conversations(calls):
    """Pose `conv_id` sur chaque appel, meme quand le chainage exact manque.

    Les appels de tour 0 n'ont aucun tour assistant a hasher. On les rattache a
    la conversation qui porte le meme (definition d'agent, prompt de tache) —
    c'est-a-dire la suite du meme fil. A defaut, ils forment leur propre
    entree `task:<suffixe>:<empreinte>`, visible plutot que silencieusement fondue.

    Threads serveur (2.1.301+) : une `continue` n'a ni premier tour assistant
    ni premier message — elle HÉRITE la conversation, le type d'acteur et la
    tâche de son prédécesseur de chaîne, traité avant elle (ordre des
    requêtes). La clé de tâche prend le prompt entier, pas ses 400 premiers
    caractères : les prompts de round d'un même goal partagent leur début.

    Une `continue` dont la réponse parente est restée orpheline (deux réponses
    du même agent à quelques jetons près, l'appariement a choisi l'autre) hérite
    de la dernière conversation de son agent : deux instances du même type
    d'agent ne tournent pas en parallèle dans pursue-goal. 5 cas au 16/10.

    Les forks du harnais (`HARNESS_FORK_MARKERS`) forment chacun une
    conversation `harness:<type>` par sorte, à soustraire avant de comparer.
    """
    last_by_actor = {}
    def task_key(r):
        return (r["actor_sig"], hashlib.sha1(r["task_text"].encode()).hexdigest()[:10])

    by_task = {}
    for c in calls:
        r = c["request"]
        if r["conv_sig"] and not r["harness_fork"] and r["thread_type"] != "continue":
            by_task.setdefault(task_key(r), r["conv_sig"])
    for c in sorted(calls, key=lambda c: c["request"]["mtime"]):
        r = c["request"]
        prev = c.get("chain_prev")
        if r["harness_fork"]:
            c["conv_id"] = f"harness:{r['harness_fork']}"
            r["actor_kind"] = f"harness:{r['harness_fork']}"
        elif r["thread_type"] == "continue" and (
            (prev is not None and "conv_id" in prev) or r["actor_sig"] in last_by_actor
        ):
            src = prev if prev is not None and "conv_id" in prev else last_by_actor[r["actor_sig"]]
            c["conv_id"] = src["conv_id"]
            r["actor_kind"] = src["request"]["actor_kind"]
            r["task_text"] = src["request"]["task_text"]
        else:
            c["conv_id"] = r["conv_sig"] or by_task.get(task_key(r)) or "task:{}:{}".format(*task_key(r))
        if not r["harness_fork"]:
            last_by_actor[r["actor_sig"]] = c
    return calls


def detect_incidents(archive_name, calls):
    incidents = []

    # (a) same skill re-invoked within a short window -> candidate retry/context-bug loop
    by_skill_session = defaultdict(list)
    for c in calls:
        # Un meme appel peut invoquer le meme skill deux fois en un tour (une
        # Phase 2 ou 4 multi-services : `app` puis `frontend`). Ce n'est pas une
        # re-invocation, c'est du parallelisme voulu — d'ou le `set()`. Sans lui
        # la capture du 07/09/2026 rendait 9 faux positifs, tous a 0 seconde de
        # fenetre et un seul appel (§M.16.5, signale deux fois, non corrige).
        for skill in {s for s in (c["response"]["skill_calls"] or "").split(";") if s}:
            by_skill_session[(c["request"]["session_id"], skill)].append(c)
    for (session_id, skill), occs in by_skill_session.items():
        occs.sort(key=lambda c: c["response"]["mtime"])
        cluster = [occs[0]]
        for c in occs[1:]:
            if c["response"]["mtime"] - cluster[-1]["response"]["mtime"] <= RETRY_WINDOW_S:
                cluster.append(c)
            else:
                if len(cluster) >= 2:
                    incidents.append(_retry_incident(archive_name, session_id, skill, cluster, calls))
                cluster = [c]
        if len(cluster) >= 2:
            incidents.append(_retry_incident(archive_name, session_id, skill, cluster, calls))

    # (b) failed calls: requests with no captured response at all
    return incidents


def _retry_incident(archive_name, session_id, skill, cluster, all_calls):
    t0, t1 = cluster[0]["response"]["mtime"], cluster[-1]["response"]["mtime"]
    window_calls = [
        c for c in all_calls
        if c["request"]["session_id"] == session_id and t0 <= c["response"]["mtime"] <= t1
    ]
    billed = sum(
        c["response"]["input_tokens"] + c["response"]["cache_read_tokens"] + c["response"]["cache_creation_tokens"]
        for c in window_calls
    )
    output = sum(c["response"]["output_tokens"] for c in window_calls)
    return {
        "type": "repeated_skill_invocation",
        "archive": archive_name,
        "session_id": session_id,
        "skill": skill,
        "n_invocations": len(cluster),
        "window_start_mtime": t0,
        "window_end_mtime": t1,
        "window_seconds": round(t1 - t0, 1),
        "n_calls_in_window": len(window_calls),
        "billed_input_tokens_in_window": billed,
        "output_tokens_in_window": output,
    }


def pct(n, d):
    return round(100 * n / d, 1) if d else 0.0


def p(values, q):
    if not values:
        return 0
    values = sorted(values)
    idx = min(len(values) - 1, int(q * len(values)))
    return values[idx]


def default_out_dir():
    """Prochain `analysis_YYYYMMDD<lettre>` libre pour aujourd'hui."""
    day = datetime.now().strftime("%Y%m%d")
    for i in range(26):
        candidate = TELEMETRY_DIR / f"analysis_{day}{chr(97 + i)}"
        if not candidate.exists():
            return candidate
    raise SystemExit(f"26 analyses deja produites le {day} — passer --out")


def latest_capture():
    """La capture la plus recente sous ~/.client-1-telemetry/api-bodies/."""
    if not CAPTURE_ROOT.is_dir():
        return None
    sessions = [d for d in CAPTURE_ROOT.iterdir() if d.is_dir()]
    if not sessions:
        return None
    return max(sessions, key=lambda d: d.stat().st_mtime)


def main():
    global OUT_DIR
    argv = sys.argv[1:]
    if "--out" in argv:
        i = argv.index("--out")
        OUT_DIR = Path(argv[i + 1])
        del argv[i:i + 2]
    if "--label" in argv:
        i = argv.index("--label")
        forced_label = argv[i + 1]
        del argv[i:i + 2]
    else:
        forced_label = None
    if argv:
        capture_paths = [Path(a) for a in argv]
        missing = [str(p) for p in capture_paths if not p.exists()]
        if missing:
            print("Not found: " + ", ".join(missing))
            return
    else:
        latest = latest_capture()
        if latest is None:
            print(f"No capture directory found under {CAPTURE_ROOT}")
            return
        capture_paths = [latest]
        print(f"No argument — using the most recent capture: {latest.name}")
    if OUT_DIR is None:
        OUT_DIR = default_out_dir()
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    print(f"Output: {OUT_DIR}")

    all_calls_rows = []
    all_chain_rows = []
    all_conv_rows = []
    all_incidents = []
    archive_summaries = []
    all_orphans = []

    for capture_path in capture_paths:
        archive_name = forced_label if forced_label and len(capture_paths) == 1 else capture_path.name
        print(f"Processing {archive_name} ...")
        requests, responses = load_archive(capture_path)
        threaded = any(r["thread_type"] for r in requests)
        if threaded:
            calls, orphan_requests, orphan_responses = match_calls_by_tokens(requests, responses)
            print("  server-side threads detected — pairing by predicted tokens")
        else:
            calls, orphan_requests, orphan_responses = match_calls(requests, responses)
        calls = link_chains(calls)
        calls = label_chains(calls)
        calls = resolve_conversations(calls)
        incidents = detect_incidents(archive_name, calls)
        all_incidents.extend(incidents)

        for c in calls:
            req, res = c["request"], c["response"]
            billed_input = res["input_tokens"] + res["cache_read_tokens"] + res["cache_creation_tokens"]
            all_calls_rows.append({
                "archive": archive_name,
                "session_id": req["session_id"],
                "req_file": req["file"],
                "chain_root": c["chain_root"],
                "turn_index": c["turn_index"],
                "req_mtime": req["mtime"],
                "resp_mtime": res["mtime"],
                "latency_s": round(c["latency_s"], 2),
                "latency_suspect": c["latency_suspect"],
                "gap_before_s": round(c["gap_before_s"], 2) if c["gap_before_s"] is not None else "",
                "model": req["model"],
                "effort": req["effort"],
                "thinking_type": req["thinking_type"],
                "thread_type": req["thread_type"],
                "pair_err": round(c["pair_err"], 3) if "pair_err" in c else "",
                "n_messages": req["n_messages"],
                "n_tools_declared": req["n_tools_declared"],
                "system_chars": req["system_chars"],
                "last_msg_chars": req["last_msg_chars"],
                "stop_reason": res["stop_reason"],
                "input_tokens_uncached": res["input_tokens"],
                "cache_read_tokens": res["cache_read_tokens"],
                "cache_creation_tokens": res["cache_creation_tokens"],
                "billed_input_tokens": billed_input,
                "output_tokens": res["output_tokens"],
                "thinking_tokens": res["thinking_tokens"],
                "text_chars": res["text_chars"],
                "n_tool_use_blocks": res["n_tool_use_blocks"],
                "tool_names": res["tool_names"],
                "skill_calls": res["skill_calls"],
                "agent_calls": res["agent_calls"],
                "chain_agent_description": c["chain_agent_description"],
                "chain_subagent_type": c["chain_subagent_type"],
                "conv_id": c["conv_id"],
                "actor_sig": req["actor_sig"],
                "actor_kind": req["actor_kind"],
            })

        for req in orphan_requests:
            all_orphans.append({
                "archive": archive_name, "session_id": req["session_id"], "file": req["file"],
                "mtime": req["mtime"], "model": req["model"],
            })

        # per-chain rollup
        chains = defaultdict(list)
        for c in calls:
            chains[c["chain_root"]].append(c)
        for root, members in chains.items():
            members.sort(key=lambda c: c["turn_index"])
            first, last = members[0], members[-1]
            billed = sum(
                m["response"]["input_tokens"] + m["response"]["cache_read_tokens"] + m["response"]["cache_creation_tokens"]
                for m in members
            )
            output = sum(m["response"]["output_tokens"] for m in members)
            tool_counter = defaultdict(int)
            for m in members:
                for t in (m["response"]["tool_names"] or "").split(";"):
                    if t:
                        tool_counter[t] += 1
            top_tools = ";".join(f"{k}:{v}" for k, v in sorted(tool_counter.items(), key=lambda kv: -kv[1])[:5])
            all_chain_rows.append({
                "archive": archive_name,
                "session_id": first["request"]["session_id"],
                "chain_root": root,
                "n_turns": len(members),
                "start_mtime": first["request"]["mtime"],
                "end_mtime": last["response"]["mtime"],
                "duration_s": round(last["response"]["mtime"] - first["request"]["mtime"], 1),
                "billed_input_tokens": billed,
                "output_tokens": output,
                "top_tools": top_tools,
                "agent_description": first["chain_agent_description"],
                "subagent_type": first["chain_subagent_type"],
            })

        # per-conversation rollup (independant du chainage exact, §M.17.5)
        convs = defaultdict(list)
        for c in calls:
            convs[c["conv_id"]].append(c)
        for conv_id, members in convs.items():
            members.sort(key=lambda c: c["request"]["mtime"])
            first, last = members[0], max(members, key=lambda c: c["response"]["mtime"])
            billed = sum(
                m["response"]["input_tokens"] + m["response"]["cache_read_tokens"] + m["response"]["cache_creation_tokens"]
                for m in members
            )
            tool_counter = defaultdict(int)
            for m in members:
                for t in (m["response"]["tool_names"] or "").split(";"):
                    if t:
                        tool_counter[t] += 1
            all_conv_rows.append({
                "archive": archive_name,
                "conv_id": conv_id,
                "actor_sig": first["request"]["actor_sig"],
                "actor_kind": first["request"]["actor_kind"],
                "n_calls": len(members),
                "start_mtime": first["request"]["mtime"],
                "duration_s": round(last["response"]["mtime"] - first["request"]["mtime"], 1),
                "billed_input_tokens": billed,
                "cache_creation_tokens": sum(m["response"]["cache_creation_tokens"] for m in members),
                "input_tokens_uncached": sum(m["response"]["input_tokens"] for m in members),
                "output_tokens": sum(m["response"]["output_tokens"] for m in members),
                # En threads, `n_messages` ne compte que le delta : la taille de
                # contexte se lit dans le facturé du plus gros appel.
                "max_n_messages": max(m["request"]["n_messages"] for m in members),
                "peak_context_tokens": max(
                    m["response"]["input_tokens"] + m["response"]["cache_read_tokens"]
                    + m["response"]["cache_creation_tokens"] for m in members
                ),
                "agent_description": "" if conv_id.startswith("harness:") else next(
                    (m["chain_agent_description"] for m in members if m["chain_agent_description"]), ""
                ),
                "top_tools": ";".join(f"{k}:{v}" for k, v in sorted(tool_counter.items(), key=lambda kv: -kv[1])[:5]),
                "task": " ".join(first["request"]["task_text"].split())[:300],
            })

        # archive-level summary
        n_calls = len(calls)
        billed_totals = [
            c["response"]["input_tokens"] + c["response"]["cache_read_tokens"] + c["response"]["cache_creation_tokens"]
            for c in calls
        ]
        cache_read_total = sum(c["response"]["cache_read_tokens"] for c in calls)
        cache_creation_total = sum(c["response"]["cache_creation_tokens"] for c in calls)
        input_uncached_total = sum(c["response"]["input_tokens"] for c in calls)
        output_total = sum(c["response"]["output_tokens"] for c in calls)
        thinking_total = sum(c["response"]["thinking_tokens"] for c in calls)
        latencies = [c["latency_s"] for c in calls if not c["latency_suspect"]]
        n_latency_suspect = sum(1 for c in calls if c["latency_suspect"])
        gaps = [c["gap_before_s"] for c in calls if c["gap_before_s"] is not None]
        model_time = sum(latencies)  # excludes suspect outliers, see LATENCY_SUSPECT_S
        gap_time = sum(g for g in gaps if g > 0)
        tool_counter = defaultdict(int)
        for c in calls:
            for t in (c["response"]["tool_names"] or "").split(";"):
                if t:
                    tool_counter[t] += 1
        n_tool_calls = sum(tool_counter.values())
        session_ids = {c["request"]["session_id"] for c in calls}
        n_roots = sum(1 for c in calls if c["chain_prev"] is None)
        cacheable = cache_read_total + cache_creation_total
        archive_summaries.append({
            "archive": archive_name,
            "n_sessions": len(session_ids),
            "n_calls": n_calls,
            "n_chains": n_roots,
            "n_failed_calls_no_response": len(orphan_requests),
            "threaded": threaded,
            # Seules les `continue` ont une prédiction exacte : c'est leur taux qui
            # dit si l'appariement tient (≈ 90 % au 16/10/2026).
            "pct_continue_pairs_within_5pct": pct(
                sum(1 for c in calls if c["request"]["thread_type"] == "continue" and c.get("pair_err", 1) < 0.05),
                sum(1 for c in calls if c["request"]["thread_type"] == "continue"),
            ) if threaded else "",
            "model_mix": ";".join(sorted({c["request"]["model"] for c in calls})),
            "effort_mix": ";".join(sorted({str(c["request"]["effort"]) for c in calls})),
            "thinking_mix": ";".join(sorted({str(c["request"]["thinking_type"]) for c in calls})),
            "wall_clock_span_s": round(max((c["response"]["mtime"] for c in calls), default=0)
                                        - min((c["request"]["mtime"] for c in calls), default=0), 1),
            "total_model_time_s": round(model_time, 1),
            "total_gap_time_s": round(gap_time, 1),
            "pct_time_model_vs_gap": pct(model_time, model_time + gap_time),
            "median_latency_s": round(statistics.median(latencies), 2) if latencies else 0,
            "p90_latency_s": round(p(latencies, 0.9), 2),
            "max_latency_s": round(max(latencies, default=0), 2),
            "n_latency_suspect_excluded": n_latency_suspect,
            "n_gaps_over_60s": sum(1 for g in gaps if g > LONG_GAP_THRESHOLD_S),
            "billed_input_tokens_total": sum(billed_totals),
            "cache_read_tokens_total": cache_read_total,
            "cache_creation_tokens_total": cache_creation_total,
            "input_uncached_tokens_total": input_uncached_total,
            "cache_hit_rate_pct": pct(cache_read_total, cacheable),
            "output_tokens_total": output_total,
            "thinking_tokens_total": thinking_total,
            "pct_output_is_thinking": pct(thinking_total, output_total),
            "n_tool_calls_total": n_tool_calls,
            "pct_tool_calls_bash": pct(tool_counter.get("Bash", 0), n_tool_calls),
            "top_tools": ";".join(f"{k}:{v}" for k, v in sorted(tool_counter.items(), key=lambda kv: -kv[1])[:8]),
        })

        print(f"  {n_calls} calls matched, {len(orphan_requests)} unanswered, {len(incidents)} incident(s) flagged")

    def write_csv(filename, rows, fieldnames):
        path = OUT_DIR / filename
        with open(path, "w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=fieldnames)
            w.writeheader()
            w.writerows(rows)
        print(f"wrote {path} ({len(rows)} rows)")

    write_csv("calls.csv", all_calls_rows, list(all_calls_rows[0].keys()) if all_calls_rows else [])
    write_csv("chains.csv", all_chain_rows, list(all_chain_rows[0].keys()) if all_chain_rows else [])
    all_conv_rows.sort(key=lambda r: -r["billed_input_tokens"])
    write_csv("conversations.csv", all_conv_rows, list(all_conv_rows[0].keys()) if all_conv_rows else [])
    write_csv("archive_summary.csv", archive_summaries, list(archive_summaries[0].keys()) if archive_summaries else [])
    write_csv("failed_calls.csv", all_orphans, list(all_orphans[0].keys()) if all_orphans else [])
    write_csv(
        "incidents_repeated_skill.csv", all_incidents,
        list(all_incidents[0].keys()) if all_incidents else [],
    )

    print(f"\nDone. See {OUT_DIR}/ for outputs.")


if __name__ == "__main__":
    main()
