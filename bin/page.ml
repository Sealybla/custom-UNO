(* The whole web UI, served as one self-contained page at "/".
   Gameplay is click-only: cards, draw pile, pass button, wild color
   picker. The single place users type is the house-rules editor, which
   submits to /api/rules and renders the parser's errors. *)
let html =
  {html|<!doctype html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Custom UNO</title>
<style>
  * { box-sizing:border-box; }
  body { font-family:system-ui,sans-serif; margin:0; min-height:100vh;
         background:radial-gradient(circle at 50% 30%, #2c8a50, #14532d); color:#fff; }
  .view { max-width:900px; margin:0 auto; padding:1rem 1.5rem; }
  h1 { text-align:center; letter-spacing:.12em; text-shadow:0 2px 4px rgba(0,0,0,.4); }
  input, textarea { font:inherit; border-radius:8px; border:none; padding:.5rem .75rem; }
  textarea { width:100%; font-family:ui-monospace,monospace; font-size:.85rem;
             background:#0f3d22; color:#d7f5e2; }
  button { font:inherit; font-weight:600; border:none; border-radius:8px;
           padding:.5rem 1rem; cursor:pointer; background:#fbbf24; color:#1a1a1a; }
  button:hover { filter:brightness(1.08); }
  .err { color:#ffd3d3; white-space:pre-wrap; font-family:ui-monospace,monospace; font-size:.85rem; }
  .ok { color:#c9f7d4; }
  .panel { background:rgba(0,0,0,.25); border-radius:14px; padding:1rem 1.25rem; margin-top:1rem; }
  #toast { position:fixed; top:12px; left:50%; transform:translateX(-50%);
           background:#7f1d1d; color:#fff; padding:.5rem 1rem; border-radius:8px;
           opacity:0; transition:opacity .25s; pointer-events:none; z-index:20; }
  #toast.show { opacity:1; }
  .card { display:inline-flex; align-items:center; justify-content:center;
          width:64px; height:96px; border-radius:10px; margin:4px; color:#fff;
          font-size:1.5rem; font-weight:800; box-shadow:0 3px 6px rgba(0,0,0,.35);
          border:4px solid #fff; user-select:none; }
  .card.Red { background:#d92b2b; } .card.Green { background:#1f9d55; }
  .card.Blue { background:#2779bd; } .card.Yellow { background:#e6a817; }
  .card.NoColor { background:#222; }
  .card.click { cursor:pointer; transition:transform .1s; }
  .card.click:hover { transform:translateY(-8px); }
  .card.back { background:repeating-linear-gradient(45deg,#7f1d1d,#7f1d1d 8px,#991b1b 8px,#991b1b 16px);
               font-size:.9rem; letter-spacing:.05em; }
  #players-bar { display:flex; gap:.75rem; justify-content:center; flex-wrap:wrap; margin-bottom:1rem; }
  .player { padding:.35rem .8rem; border-radius:999px; background:rgba(0,0,0,.35); }
  .player.turn { background:#fbbf24; color:#1a1a1a; font-weight:700; }
  #table { display:flex; align-items:center; justify-content:center; gap:1.25rem; margin:1rem 0; }
  #color-dot { width:28px; height:28px; border-radius:50%; border:3px solid #fff; }
  #hand { text-align:center; padding:.5rem; background:rgba(0,0,0,.25);
          border-radius:14px; min-height:120px; }
  #log { list-style:none; padding:0; max-width:480px; margin:1rem auto; font-size:.85rem; opacity:.85; }
  #log li { padding:.15rem 0; border-bottom:1px solid rgba(255,255,255,.12); }
  #color-modal { position:fixed; inset:0; background:rgba(0,0,0,.6);
                 display:flex; align-items:center; justify-content:center; z-index:10; }
  #color-modal .box { background:#14532d; padding:1.5rem; border-radius:14px; text-align:center; }
  #color-modal button { width:56px; height:56px; border-radius:50%; margin:.4rem; }
  .swatch-red{background:#d92b2b} .swatch-green{background:#1f9d55}
  .swatch-blue{background:#2779bd} .swatch-yellow{background:#e6a817}
  ul#lobby-players { list-style:none; padding:0; }
  ul#lobby-players li { padding:.2rem 0; }
  [hidden] { display:none !important; }
</style>
</head>
<body>
<h1>CUSTOM UNO</h1>
<div id="toast"></div>

<div id="view-join" class="view">
  <div class="panel" style="text-align:center">
    <input id="name-input" placeholder="your name" maxlength="20">
    <button id="join-btn">Join lobby</button>
    <div id="join-err" class="err"></div>
  </div>
</div>

<div id="view-lobby" class="view" hidden>
  <div class="panel">
    <h2>Lobby</h2>
    <ul id="lobby-players"></ul>
    <button id="start-btn">Start game</button>
    <span id="lobby-status" class="ok"></span>
  </div>
  <div class="panel">
    <h2>House rules</h2>
    <p style="opacity:.8">Edit the ruleset and submit it before starting a game.</p>
    <textarea id="rules-text" rows="16" spellcheck="false"></textarea>
    <p><button id="rules-btn">Submit rules</button></p>
    <pre id="rules-status"></pre>
  </div>
</div>

<div id="view-game" class="view" hidden>
  <div id="players-bar"></div>
  <div id="table">
    <div id="draw-pile" class="card back click" title="draw a card">UNO</div>
    <div id="top-card" class="card"></div>
    <div id="color-dot" title="current color"></div>
    <button id="pass-btn">Pass</button>
  </div>
  <div id="hand"></div>
  <ul id="log"></ul>
</div>

<div id="color-modal" hidden>
  <div class="box">
    <p>Pick a color</p>
    <button class="swatch-red" data-color="red"></button>
    <button class="swatch-green" data-color="green"></button>
    <button class="swatch-blue" data-color="blue"></button>
    <button class="swatch-yellow" data-color="yellow"></button>
  </div>
</div>

<script>
const VALUE_LABEL = {Zero:'0',One:'1',Two:'2',Three:'3',Four:'4',Five:'5',Six:'6',
  Seven:'7',Eight:'8',Nine:'9',Skip:'⊘',Reverse:'⇄',Plus:'+2',Wild:'W',Wild4:'+4'};
const COLOR_CSS = {Red:'#d92b2b',Green:'#1f9d55',Blue:'#2779bd',Yellow:'#e6a817',NoColor:'#222'};

const RULES_TEMPLATE = `# Standard Uno. Edit these rules to make your own variant.

rule "play wild" priority 100:
  when card is wild and your turn
  do play the card, set color to declared, advance turn

rule "play plus two" priority 100:
  when card is plus two and your turn
  do play the card, set color from card, add 2 pending draws, advance turn

rule "play skip" priority 100:
  when card is skip and your turn
  do play the card, set color from card, skip next player

rule "play reverse" priority 100:
  when card is reverse and your turn
  do play the card, set color from card, reverse direction, advance turn

rule "take penalty" priority 90:
  when pending draws > 0 and your turn
  do apply pending draws, advance turn

rule "play plus four" priority 110:
  when card is plus four and your turn
  do play the card, set color to declared, add 4 pending draws, advance turn

rule "play matching card" priority 10:
  when (card matches color or card matches value) and your turn
  do play the card, set color from card, advance turn

rule "draw a card" priority 1:
  when player draws and your turn
  do draw 1 card, advance turn
`;

let name = null;
let state = { players:[], hand:[], top:null, color:null, current:null, inGame:false };
let pendingWild = null;

const $ = id => document.getElementById(id);

function toast(msg){
  const t = $('toast'); t.textContent = msg; t.classList.add('show');
  clearTimeout(t._h); t._h = setTimeout(() => t.classList.remove('show'), 3000);
}
function logLine(msg){
  const li = document.createElement('li'); li.textContent = msg;
  const log = $('log'); log.prepend(li);
  while (log.children.length > 8) log.lastChild.remove();
}

async function api(path, opts = {}){
  const sep = path.includes('?') ? '&' : '?';
  const res = await fetch(path + sep + 'name=' + encodeURIComponent(name), opts);
  return res.json();
}

function setView(v){
  $('view-join').hidden = v !== 'join';
  $('view-lobby').hidden = v !== 'lobby';
  $('view-game').hidden = v !== 'game';
}

function apply(ev){
  switch (ev.type){
    case 'lobby':
      state.players = ev.players;
      if (!state.inGame) setView('lobby');
      break;
    case 'game_started':
      state.inGame = true; state.hand = ev.hand; state.top = ev.top_card;
      state.color = ev.current_color; state.players = ev.players;
      state.current = ev.current_player;
      $('log').innerHTML = ''; setView('game');
      break;
    case 'hand': state.hand = ev.hand; break;
    case 'pile': state.top = ev.top_card; state.color = ev.current_color; break;
    case 'turn': state.current = ev.player; break;
    case 'uno': logLine('UNO! ' + ev.player + ' has one card left'); break;
    case 'game_over':
      state.inGame = false;
      toast(ev.winner + ' wins!');
      $('lobby-status').textContent = 'Last game: ' + ev.winner + ' won';
      setView('lobby');
      break;
    case 'rules_updated':
      $('rules-status').textContent = ev.player + ' set ' + ev.num_rules + ' house rules';
      $('rules-status').className = 'ok';
      logLine(ev.player + ' updated the rules');
      break;
    case 'rejected': toast(ev.reason); break;
  }
}

function render(){
  const lp = $('lobby-players'); lp.innerHTML = '';
  for (const p of state.players){
    const li = document.createElement('li');
    li.textContent = p === name ? p + ' (you)' : p;
    lp.append(li);
  }
  if (!state.inGame) return;
  const bar = $('players-bar'); bar.innerHTML = '';
  for (const p of state.players){
    const d = document.createElement('div');
    d.className = 'player' + (p === state.current ? ' turn' : '');
    d.textContent = p === name ? p + ' (you)' : p;
    bar.append(d);
  }
  if (state.top){
    const t = $('top-card');
    t.className = 'card ' + state.top.color;
    t.textContent = VALUE_LABEL[state.top.value] || state.top.value;
  }
  $('color-dot').style.background = COLOR_CSS[state.color] || '#222';
  const hand = $('hand'); hand.innerHTML = '';
  for (const c of state.hand){
    const el = document.createElement('div');
    el.className = 'card click ' + c.color;
    el.textContent = VALUE_LABEL[c.value] || c.value;
    el.onclick = () => playCard(c);
    hand.append(el);
  }
}

async function playCard(card){
  if (card.value === 'Wild' || card.value === 'Wild4'){
    pendingWild = card;
    $('color-modal').hidden = false;
    return;
  }
  const r = await api('/api/play?card_id=' + card.id, {method:'POST'});
  if (!r.ok) toast(r.error);
}

document.querySelectorAll('#color-modal button').forEach(b => {
  b.onclick = async () => {
    $('color-modal').hidden = true;
    if (!pendingWild) return;
    const r = await api('/api/play?card_id=' + pendingWild.id + '&color=' + b.dataset.color,
                        {method:'POST'});
    if (!r.ok) toast(r.error);
    pendingWild = null;
  };
});

$('draw-pile').onclick = async () => {
  const r = await api('/api/draw', {method:'POST'}); if (!r.ok) toast(r.error);
};
$('pass-btn').onclick = async () => {
  const r = await api('/api/pass', {method:'POST'}); if (!r.ok) toast(r.error);
};
$('start-btn').onclick = async () => {
  const r = await api('/api/start', {method:'POST'}); if (!r.ok) toast(r.error);
};
$('rules-btn').onclick = async () => {
  const r = await api('/api/rules', {method:'POST', body: $('rules-text').value});
  const s = $('rules-status');
  if (r.ok){ s.textContent = 'Rules accepted'; s.className = 'ok'; }
  else { s.textContent = r.error; s.className = 'err'; }
};

$('join-btn').onclick = async () => {
  const v = $('name-input').value.trim();
  if (!v) return;
  name = v;
  try {
    const r = await api('/api/join', {method:'POST'});
    if (!r.ok){ $('join-err').textContent = r.error; name = null; return; }
    setView('lobby');
    startPolling();
  } catch (e){ $('join-err').textContent = 'server unreachable'; name = null; }
};
$('name-input').addEventListener('keydown', e => { if (e.key === 'Enter') $('join-btn').click(); });

let polling = null;
function startPolling(){
  if (polling) return;
  polling = setInterval(async () => {
    try {
      const r = await api('/api/poll');
      if (r.ok && r.events.length){ r.events.forEach(apply); render(); }
    } catch (e){ /* transient */ }
  }, 700);
}

// tell the server we're gone the instant the tab closes, so a bot can take
// over immediately instead of waiting for the poll-silence timeout. sendBeacon
// survives page unload where a normal fetch would be cancelled.
window.addEventListener('pagehide', () => {
  if (name) navigator.sendBeacon('/api/leave?name=' + encodeURIComponent(name));
});

$('rules-text').value = RULES_TEMPLATE;
</script>
</body>
</html>
|html}
;;
