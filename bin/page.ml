(* The whole web UI, served as one self-contained page at "/".
   UNO pop-art theme: hero splash lobby, oval game table with opponents'
   card backs fanned around it, flying card animations. Gameplay is
   click-only; the single typing surface is the house-rules editor.
   NOTE: the byte sequence "| html}" (without the space) must never appear
   inside the string below — it would terminate the OCaml quoted literal. *)
let html =
  {html|<!doctype html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Custom UNO</title>
<style>
  :root {
    --c-red:#e0332c; --c-yellow:#ffce00; --c-blue:#0a6bbd; --c-green:#18a850;
    --ink:#161418; --paper:#fffdf7;
    --bg-red-1:#c2261f; --bg-red-2:#8f1613;
    --felt-1:#28797f; --felt-2:#123e42;
    --card-w: clamp(54px, 6.5vw, 82px);
    --mini-w: clamp(20px, 2.4vw, 30px);
    --shadow-card: 0 4px 10px rgba(0,0,0,.35);
    --ease-pop: cubic-bezier(.3,1.4,.4,1);
  }
  * { box-sizing:border-box; }
  html, body { height:100%; }
  body { font-family:system-ui,sans-serif; margin:0; color:#fff; background:var(--bg-red-2); overflow-x:hidden; }
  /* rotating pop-art sunburst behind the lobby */
  body::before { content:''; position:fixed; left:50%; top:50%; width:250vmax; height:250vmax;
    margin:-125vmax 0 0 -125vmax; z-index:-2;
    background:repeating-conic-gradient(var(--bg-red-1) 0 9deg, var(--bg-red-2) 9deg 18deg);
    animation:spin 90s linear infinite; }
  body::after { content:''; position:fixed; inset:0; z-index:-1; pointer-events:none;
    background:radial-gradient(circle at 50% 40%, transparent 30%, rgba(0,0,0,.55)); }
  @keyframes spin { to { transform:rotate(360deg); } }

  /* ============ cards ============ */
  .card { position:relative; display:inline-flex; align-items:center; justify-content:center;
    width:var(--card-w); height:calc(var(--card-w)*1.5);
    font-size:calc(var(--card-w)*.52); border-radius:calc(var(--card-w)*.13);
    background:var(--ink); color:#fff; box-shadow:var(--shadow-card);
    overflow:hidden; user-select:none; flex:none; }
  .card::before { content:''; position:absolute; inset:0; border-radius:inherit; z-index:3;
    box-shadow:inset 0 0 0 calc(var(--card-w)*.055) #fff; pointer-events:none; }
  .card .ellipse { position:absolute; width:150%; height:62%; left:50%; top:50%;
    transform:translate(-50%,-50%) rotate(-32deg); border-radius:50%;
    background:var(--paper); z-index:1; }
  .card .glyph { position:relative; z-index:2; font-weight:900; font-style:italic;
    text-shadow:.05em .05em 0 rgba(0,0,0,.25); line-height:1; }
  .card .ix { position:absolute; z-index:2; font-size:.3em; font-weight:900; font-style:italic;
    color:#fff; text-shadow:.1em .1em 0 rgba(0,0,0,.35); line-height:1; }
  .card .ix.tl { top:.5em; left:.6em; }
  .card .ix.br { bottom:.5em; right:.6em; transform:rotate(180deg); }
  .card.Red { background:var(--c-red); }     .card.Red .glyph { color:var(--c-red); }
  .card.Green { background:var(--c-green); } .card.Green .glyph { color:var(--c-green); }
  .card.Blue { background:var(--c-blue); }   .card.Blue .glyph { color:var(--c-blue); }
  .card.Yellow { background:var(--c-yellow); } .card.Yellow .glyph { color:#c79c00; }
  .card.NoColor .ellipse { background:conic-gradient(var(--c-red) 0 25%, var(--c-blue) 0 50%,
    var(--c-yellow) 0 75%, var(--c-green) 0); }
  .card.NoColor .glyph { color:#fff; text-shadow:.06em .06em 0 rgba(0,0,0,.6); }
  .card.back .ellipse { background:var(--c-red); }
  .card.back .glyph { color:var(--c-yellow); font-size:.62em; transform:rotate(-12deg);
    text-shadow:.06em .06em 0 rgba(0,0,0,.45); letter-spacing:.01em; }
  .card.mini { --card-w: var(--mini-w); box-shadow:0 2px 4px rgba(0,0,0,.4); }
  .flying { position:fixed; z-index:60; margin:0; pointer-events:none; }

  /* ============ hero (join + lobby) ============ */
  .hero { min-height:100dvh; display:flex; flex-direction:column; align-items:center;
    padding:5vh 16px 4vh; position:relative; z-index:1; }
  .deco { position:fixed; z-index:0; pointer-events:none; opacity:.92;
    animation:floaty 7s ease-in-out infinite; }
  @keyframes floaty { 50% { translate:0 -16px; } }
  .logo { position:relative; display:grid; place-items:center; transform:rotate(-6deg);
    width:min(380px,84vw); height:min(160px,36vw); border-radius:50%;
    background:var(--c-red); border:6px solid var(--c-yellow);
    box-shadow:inset 0 0 0 4px #fff, 0 12px 0 rgba(0,0,0,.25), 0 24px 50px rgba(0,0,0,.4); }
  .logo .uno { font-size:clamp(3rem,13vw,5.2rem); font-weight:900; font-style:italic;
    color:var(--c-yellow); -webkit-text-stroke:2px #fff;
    text-shadow:4px 4px 0 rgba(0,0,0,.3); letter-spacing:-.03em; }
  .logo .strip { position:absolute; bottom:-.9rem; background:var(--paper); color:var(--ink);
    font-weight:900; letter-spacing:.45em; padding:.25rem .9rem .25rem 1.2rem;
    border-radius:6px; transform:rotate(3deg); font-size:.9rem;
    box-shadow:0 4px 0 rgba(0,0,0,.25); }
  .panel { position:relative; z-index:2; width:min(520px,94vw);
    background:rgba(24,12,12,.62); backdrop-filter:blur(10px);
    border-radius:18px; border-top:6px solid var(--c-yellow);
    padding:1.1rem 1.4rem 1.3rem; margin-top:1.6rem;
    box-shadow:0 18px 50px rgba(0,0,0,.45); }
  .panel h2 { margin:.2rem 0 .8rem; font-style:italic; letter-spacing:.04em; }
  input, textarea { font:inherit; border-radius:10px; border:none; padding:.6rem .8rem; }
  textarea { width:100%; font-family:ui-monospace,monospace; font-size:.85rem;
    background:#140c0c; color:#ffe9c9; border:1px solid rgba(255,206,0,.25); }
  button { font:inherit; font-weight:800; border:none; border-radius:999px;
    padding:.6rem 1.4rem; cursor:pointer; background:var(--c-yellow); color:var(--ink);
    box-shadow:0 4px 0 rgba(0,0,0,.3); transition:transform .12s var(--ease-pop); }
  button:hover { transform:translateY(-2px) scale(1.03); }
  button:active { transform:translateY(1px); }
  .err { color:#ffd3d3; white-space:pre-wrap; font-family:ui-monospace,monospace; font-size:.85rem; }
  .ok { color:#c9f7d4; }
  #rules-status { border-radius:10px; padding:.5rem .7rem; margin:.6rem 0 0; }
  #rules-status.err { background:rgba(224,51,44,.25); }
  #rules-status.ok { background:rgba(24,168,80,.25); }
  #rules-status:empty { display:none; }
  ul#lobby-players { list-style:none; padding:0; margin:.2rem 0 1rem; display:flex;
    flex-wrap:wrap; gap:.5rem; }
  ul#lobby-players li { background:rgba(255,255,255,.14); border-radius:999px;
    padding:.35rem .9rem; font-weight:700; }
  @media (min-width:1000px){
    .lobby-grid { display:grid; grid-template-columns:1fr 1fr; gap:1.2rem;
      width:min(1060px,96vw); align-items:start; }
    .lobby-grid .panel { width:auto; }
  }

  /* ============ game view ============ */
  #view-game { position:fixed; inset:0; overflow:hidden; z-index:2;
    background:radial-gradient(circle at 50% 15%, #35333f, #141319 70%); }
  #table-oval { position:absolute; left:50%; top:50%; transform:translate(-50%,-52%);
    width:min(80vw,900px); height:min(54vh,480px); border-radius:50%;
    background:radial-gradient(ellipse at 50% 32%, var(--felt-1), var(--felt-2));
    box-shadow:inset 0 0 70px rgba(0,0,0,.5), 0 0 0 12px var(--c-red),
      0 0 0 16px rgba(255,255,255,.9), 0 30px 70px rgba(0,0,0,.55); }
  .table-center { position:absolute; left:50%; top:48%; transform:translate(-50%,-50%);
    display:flex; align-items:center; gap:calc(var(--card-w)*.5); z-index:2; }
  .pile { position:relative; width:var(--card-w); height:calc(var(--card-w)*1.5); }
  .pile .card { position:absolute; inset:0; }
  #draw-pile { cursor:pointer; }
  #draw-pile .card:nth-child(1){ transform:translate(-4px,4px) rotate(-4deg); }
  #draw-pile .card:nth-child(2){ transform:translate(2px,-1px) rotate(2deg); }
  #draw-pile:hover .card:nth-child(3){ transform:translateY(-8px); }
  #draw-pile .card { transition:transform .15s; }
  #discard { border-radius:calc(var(--card-w)*.13);
    box-shadow:0 0 0 5px var(--cur,#333), 0 0 26px var(--cur,transparent);
    transition:box-shadow .35s; }
  #discard .card { transform:rotate(var(--tilt,0deg)); }
  #seats { position:absolute; inset:0; z-index:3; pointer-events:none; }
  .seat { position:absolute; transform:translate(-50%,-50%); text-align:center; }
  .seat .fan { display:flex; justify-content:center; align-items:flex-end;
    height:calc(var(--mini-w)*1.9); }
  .seat .fan .card { margin-left:calc(var(--mini-w)*-.55); }
  .seat .fan .card:first-child { margin-left:0; }
  .seat .plate { display:inline-flex; align-items:center; gap:.4rem; margin-top:5px;
    background:rgba(0,0,0,.6); border-radius:999px; padding:.22rem .8rem;
    font-weight:800; font-size:.85rem; white-space:nowrap; }
  .seat.turn { filter:drop-shadow(0 0 14px rgba(255,206,0,.85)); }
  .seat.turn .plate { background:var(--c-yellow); color:var(--ink); animation:pulse 1.2s ease-in-out infinite; }
  @keyframes pulse { 50% { transform:scale(1.07); } }
  .count { display:inline-block; min-width:1.4rem; text-align:center;
    background:rgba(255,255,255,.25); border-radius:999px; padding:0 .35rem; font-size:.8rem; }
  .seat.turn .count { background:rgba(0,0,0,.2); }
  .count.uno { background:var(--c-red); color:#fff; animation:unopop .4s var(--ease-pop); }
  @keyframes unopop { from { transform:scale(0); } }
  #turn-banner { position:absolute; left:50%; bottom:calc(var(--card-w)*1.5 + 74px);
    transform:translateX(-50%); z-index:6; background:var(--c-yellow); color:var(--ink);
    font-weight:900; font-style:italic; letter-spacing:.08em; padding:.35rem 1.2rem;
    border-radius:999px; box-shadow:0 4px 0 rgba(0,0,0,.3); animation:pulse 1.2s ease-in-out infinite; }
  #hand-area { position:absolute; left:0; right:0; bottom:0; z-index:5;
    display:flex; align-items:flex-end; justify-content:center; gap:1rem;
    padding:0 12px 16px; pointer-events:none; }
  #hand-area > * { pointer-events:auto; }
  #hand { position:relative; white-space:nowrap; height:calc(var(--card-w)*1.85); display:flex; align-items:flex-end; }
  .slot { display:inline-block; position:relative; }
  .slot + .slot { margin-left:calc(-1 * var(--overlap,20px)); }
  .slot .card { transform:rotate(var(--rot,0deg)) translateY(var(--ty,0px));
    transform-origin:50% 130%; transition:transform .25s var(--ease-pop); cursor:pointer; }
  .slot:hover { z-index:7; }
  .slot:hover .card { transform:rotate(var(--rot,0deg)) translateY(calc(var(--ty,0px) - 28px)) scale(1.12); }
  #pass-btn { margin-bottom:calc(var(--card-w)*.4); }
  #log { position:absolute; left:14px; bottom:12px; z-index:4; list-style:none; margin:0;
    padding:0; font-size:.78rem; opacity:.75; max-width:230px; }
  #log li { padding:.12rem 0; border-bottom:1px solid rgba(255,255,255,.12); }
  #game-logo { position:absolute; top:10px; left:16px; z-index:4; font-weight:900;
    font-style:italic; color:var(--c-yellow); -webkit-text-stroke:1px #fff;
    font-size:1.5rem; text-shadow:2px 2px 0 rgba(0,0,0,.4); transform:rotate(-4deg); }

  /* ============ overlays ============ */
  #toast { position:fixed; top:14px; left:50%; transform:translateX(-50%) translateY(-80px);
    background:var(--c-red); color:#fff; font-weight:800; padding:.55rem 1.2rem;
    border-radius:999px; box-shadow:0 6px 0 rgba(0,0,0,.3); z-index:70;
    transition:transform .3s var(--ease-pop); pointer-events:none; max-width:88vw; }
  #toast.show { transform:translateX(-50%) translateY(0); }
  #color-modal { position:fixed; inset:0; background:rgba(0,0,0,.65);
    display:flex; align-items:center; justify-content:center; z-index:30; }
  #color-modal .wheel { width:min(300px,74vw); aspect-ratio:1; border-radius:50%;
    overflow:hidden; display:grid; grid-template:1fr 1fr / 1fr 1fr; gap:8px; padding:8px;
    background:var(--paper); transform:rotate(45deg);
    box-shadow:0 0 0 6px #fff, 0 20px 60px rgba(0,0,0,.5);
    animation:wheelin .35s var(--ease-pop); }
  @keyframes wheelin { from { transform:rotate(45deg) scale(.5); opacity:0; } }
  #color-modal .wheel button { border-radius:12px; box-shadow:none; padding:0; }
  #color-modal .wheel button:hover { transform:scale(1.05); }
  .swatch-red{background:var(--c-red)} .swatch-green{background:var(--c-green)}
  .swatch-blue{background:var(--c-blue)} .swatch-yellow{background:var(--c-yellow)}
  #uno-splash { position:fixed; left:50%; top:38%; transform:translate(-50%,-50%) rotate(-6deg);
    z-index:40; font-size:clamp(2.5rem,9vw,4.5rem); font-weight:900; font-style:italic;
    color:var(--c-yellow); -webkit-text-stroke:2px #fff;
    text-shadow:5px 5px 0 rgba(0,0,0,.4); pointer-events:none;
    animation:unopop .45s var(--ease-pop); }
  #win-overlay { position:fixed; inset:0; z-index:50; background:rgba(10,6,10,.82);
    display:flex; flex-direction:column; align-items:center; justify-content:center; gap:1.4rem;
    overflow:hidden; }
  #win-overlay .win-name { font-size:clamp(2.6rem,10vw,5rem); font-weight:900; font-style:italic;
    color:var(--c-yellow); -webkit-text-stroke:2px #fff; text-shadow:5px 5px 0 rgba(0,0,0,.45);
    transform:rotate(-5deg); animation:unopop .5s var(--ease-pop); }
  #win-overlay .win-sub { font-size:1.4rem; font-weight:800; letter-spacing:.2em; }
  #win-overlay i { position:absolute; top:-8vh; width:10px; height:16px; border-radius:2px;
    left:var(--x); animation:fall var(--d) linear var(--dl) infinite; }
  @keyframes fall { to { transform:translateY(120vh) rotate(720deg); } }
  .c1{background:var(--c-red)} .c2{background:var(--c-yellow)}
  .c3{background:var(--c-blue)} .c4{background:var(--c-green)}
  [hidden] { display:none !important; }

  @media (max-width:760px){
    #table-oval { width:96vw; height:44vh; }
    #log { display:none; }
    .seat .plate { font-size:.72rem; padding:.15rem .55rem; }
    :root { --mini-w:18px; }
  }
  @media (prefers-reduced-motion: reduce){
    *, *::before, *::after { animation:none !important; transition:none !important; }
  }
</style>
</head>
<body>
<div id="toast"></div>

<div id="hero" class="hero" aria-label="CUSTOM UNO">
  <div class="deco card back" style="--card-w:96px; left:6vw; top:12vh; rotate:-14deg; animation-delay:-2s"><span class="ellipse"></span><span class="glyph">UNO</span></div>
  <div class="deco card Red" style="--card-w:76px; right:8vw; top:9vh; rotate:12deg; animation-delay:-4s"><span class="ellipse"></span><span class="glyph">7</span></div>
  <div class="deco card Blue" style="--card-w:64px; left:12vw; bottom:14vh; rotate:9deg; animation-delay:-1s"><span class="ellipse"></span><span class="glyph">+2</span></div>
  <div class="deco card Yellow" style="--card-w:88px; right:10vw; bottom:10vh; rotate:-8deg; animation-delay:-5s"><span class="ellipse"></span><span class="glyph">⇄</span></div>
  <div class="deco card Green" style="--card-w:58px; left:38vw; top:6vh; rotate:5deg; animation-delay:-3s"><span class="ellipse"></span><span class="glyph">⊘</span></div>
  <div class="deco card NoColor" style="--card-w:70px; right:34vw; bottom:6vh; rotate:-5deg; animation-delay:-6s"><span class="ellipse"></span><span class="glyph">W</span></div>

  <div class="logo"><span class="uno">UNO</span><span class="strip">CUSTOM</span></div>

  <div id="view-join" class="panel" style="text-align:center">
    <h2>Pull up a chair</h2>
    <input id="name-input" placeholder="your name" maxlength="20">
    <button id="join-btn">Join lobby</button>
    <div id="join-err" class="err"></div>
  </div>

  <div id="view-lobby" class="lobby-grid" hidden>
    <div class="panel">
      <h2>Lobby</h2>
      <ul id="lobby-players"></ul>
      <button id="start-btn">Start game</button>
      <div id="lobby-status" class="ok" style="margin-top:.6rem"></div>
    </div>
    <div class="panel">
      <h2>House rules</h2>
      <p style="opacity:.8; margin-top:0">Edit the ruleset and submit it before starting a game.</p>
      <textarea id="rules-text" rows="14" spellcheck="false"></textarea>
      <p style="margin:.7rem 0 0"><button id="rules-btn">Submit rules</button></p>
      <pre id="rules-status"></pre>
    </div>
  </div>
</div>

<div id="view-game" hidden>
  <div id="game-logo">UNO</div>
  <div id="table-oval"></div>
  <div id="seats"></div>
  <div class="table-center">
    <div id="draw-pile" class="pile" title="draw a card"></div>
    <div id="discard" class="pile"></div>
  </div>
  <div id="turn-banner" hidden>YOUR TURN</div>
  <div id="hand-area">
    <div id="hand"></div>
    <button id="pass-btn">Pass</button>
  </div>
  <ul id="log"></ul>
</div>

<div id="color-modal" hidden>
  <div class="wheel">
    <button class="swatch-red" data-color="red"></button>
    <button class="swatch-yellow" data-color="yellow"></button>
    <button class="swatch-green" data-color="green"></button>
    <button class="swatch-blue" data-color="blue"></button>
  </div>
</div>

<div id="uno-splash" hidden></div>
<div id="win-overlay" hidden>
  <div class="win-name"></div>
  <div class="win-sub">WINS THE GAME</div>
  <button id="win-back">Back to lobby</button>
</div>

<script>
const VALUE_LABEL = {Zero:'0',One:'1',Two:'2',Three:'3',Four:'4',Five:'5',Six:'6',
  Seven:'7',Eight:'8',Nine:'9',Skip:'⊘',Reverse:'⇄',Plus:'+2',Wild:'W',Wild4:'+4'};
const COLOR_CSS = {Red:'#e0332c',Green:'#18a850',Blue:'#0a6bbd',Yellow:'#ffce00',NoColor:'#333'};

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
let state = { players:[], hand:[], top:null, color:null, current:null,
              counts:{}, inGame:false, pileStack:[] };
let pendingWild = null;
let lastPlayedId = null;
let snapshotMode = false;
const reducedMotion = matchMedia('(prefers-reduced-motion: reduce)').matches;
const dirty = { lobby:false, seats:false, pile:false, hand:false, turn:false };

const $ = id => document.getElementById(id);
const rect = el => el.getBoundingClientRect();

/* ---------- card factories ---------- */
function cardEl(card, mini){
  const el = document.createElement('div');
  el.className = 'card ' + card.color + (mini ? ' mini' : '');
  el.dataset.cid = card.id;
  const label = VALUE_LABEL[card.value] || card.value;
  el.innerHTML = '<span class="ix tl"></span><span class="ellipse"></span>' +
                 '<span class="glyph"></span><span class="ix br"></span>';
  el.querySelector('.glyph').textContent = label;
  el.querySelector('.ix.tl').textContent = label;
  el.querySelector('.ix.br').textContent = label;
  return el;
}
function cardBackEl(mini){
  const el = document.createElement('div');
  el.className = 'card back' + (mini ? ' mini' : '');
  el.innerHTML = '<span class="ellipse"></span><span class="glyph">UNO</span>';
  return el;
}
const tiltOf = id => ((id * 37) % 21) - 10;   // deterministic messy-pile tilt

/* ---------- small ui helpers ---------- */
function toast(msg){
  const t = $('toast'); t.textContent = msg; t.classList.add('show');
  clearTimeout(t._h); t._h = setTimeout(() => t.classList.remove('show'), 3000);
}
function logLine(msg){
  const li = document.createElement('li'); li.textContent = msg;
  const log = $('log'); log.prepend(li);
  while (log.children.length > 6) log.lastChild.remove();
}
function setView(v){
  $('hero').hidden = v === 'game';
  $('view-join').hidden = v !== 'join';
  $('view-lobby').hidden = v !== 'lobby';
  $('view-game').hidden = v !== 'game';
}
function unoSplash(who){
  const s = $('uno-splash'); s.textContent = 'UNO! ' + who; s.hidden = false;
  clearTimeout(s._h); s._h = setTimeout(() => { s.hidden = true; }, 1700);
}
function showWin(winner){
  const w = $('win-overlay');
  w.querySelector('.win-name').textContent = winner;
  if (!w.querySelector('i')){
    for (let i = 0; i < 40; i++){
      const f = document.createElement('i');
      f.className = 'c' + (1 + i % 4);
      f.style.setProperty('--x', (Math.random() * 100) + 'vw');
      f.style.setProperty('--d', (2.4 + Math.random() * 2.4) + 's');
      f.style.setProperty('--dl', (-Math.random() * 4) + 's');
      w.append(f);
    }
  }
  w.hidden = false;
}

async function api(path, opts = {}){
  const sep = path.includes('?') ? '&' : '?';
  const res = await fetch(path + sep + 'name=' + encodeURIComponent(name), opts);
  return res.json();
}

/* ---------- event reducer: mutates state, collects animation intents ---------- */
function apply(ev, fx){
  switch (ev.type){
    case 'lobby':
      state.players = ev.players; dirty.lobby = true;
      if (!state.inGame) setView('lobby');
      break;
    case 'game_started':
      state.inGame = true; state.hand = ev.hand; state.top = ev.top_card;
      state.color = ev.current_color; state.players = ev.players;
      state.current = ev.current_player; state.counts = {};
      state.pileStack = [ev.top_card];
      dirty.seats = dirty.pile = dirty.hand = dirty.turn = true;
      $('log').innerHTML = ''; $('win-overlay').hidden = true;
      setView('game'); layoutSeats();
      break;
    case 'hand': {
      if (fx){
        const oldIds = new Set(state.hand.map(c => c.id));
        const fresh = ev.hand.filter(c => !oldIds.has(c.id));
        if (fresh.length && !fx.some(f => f.kind === 'ownPlay'))
          fresh.forEach((c, i) => fx.push({kind:'ownDraw', id:c.id, delay:i*90,
                                           from:rect($('draw-pile'))}));
      }
      state.hand = ev.hand; dirty.hand = true;
      break;
    }
    case 'pile': {
      const changed = !state.top || state.top.id !== ev.top_card.id;
      if (changed){
        if (fx){
          if (ev.top_card.id === lastPlayedId){
            const el = document.querySelector('#hand .slot[data-cid="' + lastPlayedId + '"]');
            fx.push({kind:'ownPlay', card:ev.top_card, from: el ? rect(el) : null});
          } else {
            const seat = seatOf(state.current);
            fx.push({kind:'oppPlay', card:ev.top_card,
                     from: seat ? rect(seat) : rect($('draw-pile'))});
          }
        }
        lastPlayedId = null;
        state.pileStack.push(ev.top_card);
        if (state.pileStack.length > 4) state.pileStack.shift();
      }
      state.top = ev.top_card; state.color = ev.current_color; dirty.pile = true;
      break;
    }
    case 'turn': state.current = ev.player; dirty.turn = dirty.seats = true; break;
    case 'hand_counts': {
      if (fx){
        for (const [p, n] of ev.counts){
          const old = state.counts[p];
          if (old !== undefined && n > old && p !== name)
            fx.push({kind:'oppDraw', player:p, count:n-old, from:rect($('draw-pile'))});
        }
      }
      state.counts = Object.fromEntries(ev.counts); dirty.seats = true;
      break;
    }
    case 'uno': unoSplash(ev.player); logLine('UNO! ' + ev.player); break;
    case 'game_over':
      state.inGame = false;
      $('lobby-status').textContent = 'Last game: ' + ev.winner + ' won';
      showWin(ev.winner);
      break;
    case 'rules_updated':
      $('rules-status').textContent = ev.player + ' set ' + ev.num_rules + ' house rules';
      $('rules-status').className = 'ok';
      logLine(ev.player + ' updated the rules');
      break;
    case 'rejected': toast(ev.reason); break;
  }
}

/* ---------- targeted renderers ---------- */
function render(){
  if (dirty.lobby){ renderLobby(); dirty.lobby = false; }
  if (!state.inGame){ dirty.seats = dirty.pile = dirty.hand = dirty.turn = false; return; }
  if (dirty.seats){ renderSeats(); dirty.seats = false; }
  if (dirty.pile){ renderPile(); dirty.pile = false; }
  if (dirty.hand){ renderHand(); dirty.hand = false; }
  if (dirty.turn){ $('turn-banner').hidden = state.current !== name; dirty.turn = false; }
}

function renderLobby(){
  const lp = $('lobby-players'); lp.innerHTML = '';
  for (const p of state.players){
    const li = document.createElement('li');
    li.textContent = p === name ? p + ' (you)' : p;
    lp.append(li);
  }
}

function seatOf(player){
  return document.querySelector('.seat[data-player="' + (CSS && CSS.escape ? CSS.escape(player) : player) + '"]');
}

function layoutSeats(){
  const i0 = state.players.indexOf(name);
  const opp = i0 < 0 ? state.players.slice()
    : state.players.slice(i0 + 1).concat(state.players.slice(0, i0));
  const seatsEl = $('seats');
  seatsEl.dataset.opponents = opp.join(' ');
  const k = opp.length, cx = 50, cy = 54, rx = 44, ry = 40;
  opp.forEach((p, j) => {
    const t = (j + 1) / (k + 1);
    const th = (165 - 150 * t) * Math.PI / 180;
    const s = seatOf(p);
    if (!s) return;
    s.style.left = (cx + rx * Math.cos(th)) + '%';
    s.style.top = (cy - ry * Math.sin(th)) + '%';
  });
}

function renderSeats(){
  const i0 = state.players.indexOf(name);
  const opp = i0 < 0 ? state.players.slice()
    : state.players.slice(i0 + 1).concat(state.players.slice(0, i0));
  const seatsEl = $('seats');
  seatsEl.innerHTML = '';
  for (const p of opp){
    const s = document.createElement('div');
    s.className = 'seat' + (p === state.current ? ' turn' : '');
    s.dataset.player = p;
    const fan = document.createElement('div'); fan.className = 'fan';
    const n = state.counts[p];
    const shown = Math.min(n === undefined ? 7 : n, 10);
    for (let i = 0; i < shown; i++){
      const b = cardBackEl(true);
      const mid = (shown - 1) / 2;
      b.style.transform = 'rotate(' + ((i - mid) * 7) + 'deg)' +
                          ' translateY(' + (Math.abs(i - mid) * 2.5) + 'px)';
      fan.append(b);
    }
    const plate = document.createElement('div'); plate.className = 'plate';
    plate.textContent = p;
    if (n !== undefined){
      const b = document.createElement('span');
      b.className = 'count' + (n === 1 ? ' uno' : '');
      b.textContent = n === 1 ? 'UNO!' : n;
      plate.append(b);
    }
    s.append(fan, plate);
    seatsEl.append(s);
  }
  layoutSeats();
}

function renderPile(){
  const d = $('discard');
  d.innerHTML = '';
  for (const c of state.pileStack){
    const el = cardEl(c);
    el.style.setProperty('--tilt', tiltOf(c.id) + 'deg');
    d.append(el);
  }
  d.style.setProperty('--cur', COLOR_CSS[state.color] || '#333');
}

function makeSlot(card){
  const slot = document.createElement('div');
  slot.className = 'slot';
  slot.dataset.cid = card.id;
  const el = cardEl(card);
  el.onclick = () => playCard(card);
  slot.append(el);
  return slot;
}

function renderHand(){
  const handEl = $('hand');
  const have = new Map([...handEl.children].map(s => [s.dataset.cid, s]));
  const before = new Map();
  for (const [id, s] of have) before.set(id, rect(s));
  for (const c of state.hand){
    const s = have.get(String(c.id));
    handEl.append(s || makeSlot(c));
  }
  for (const [id, s] of have)
    if (!state.hand.some(c => String(c.id) === id)) s.remove();
  setFan();
  if (reducedMotion || snapshotMode) return;
  for (const s of handEl.children){
    const r0 = before.get(s.dataset.cid);
    if (!r0) continue;
    const dx = r0.left - rect(s).left;
    if (Math.abs(dx) > 1)
      s.animate([{transform:'translateX(' + dx + 'px)'}, {transform:'none'}],
                {duration:250, easing:'ease-out'});
  }
}

function setFan(){
  const handEl = $('hand');
  const slots = [...handEl.children];
  const n = slots.length;
  if (!n) return;
  const cw = rect(slots[0]).width || 70;
  const avail = Math.min(window.innerWidth - 200, 760);
  const ov = n > 1 ? Math.max(cw * .25, (n * cw - avail) / (n - 1)) : 0;
  handEl.style.setProperty('--overlap', Math.min(ov, cw * .75) + 'px');
  const mid = (n - 1) / 2;
  const spread = Math.min(36, n * 5);
  slots.forEach((slot, i) => {
    const off = mid ? (i - mid) / mid : 0;
    slot.firstChild.style.setProperty('--rot', (off * spread / 2) + 'deg');
    slot.firstChild.style.setProperty('--ty', (off * off * 14) + 'px');
  });
}

/* ---------- flight animations ---------- */
function flyClone(node, from, to, opts = {}){
  node.classList.add('flying');
  node.style.left = from.left + 'px';
  node.style.top = from.top + 'px';
  node.style.setProperty('--card-w', from.width + 'px');
  document.body.append(node);
  const dx = to.left + to.width/2 - (from.left + from.width/2);
  const dy = to.top + to.height/2 - (from.top + from.height/2);
  const sc = to.width / Math.max(from.width, 1);
  const anim = node.animate(
    [{transform:'translate(0,0) scale(1)'},
     {transform:'translate(' + dx + 'px,' + dy + 'px) scale(' + sc + ')'}],
    {duration:opts.dur || 430, easing:'cubic-bezier(.3,.7,.2,1)',
     delay:opts.delay || 0, fill:'both'});
  anim.finished.then(() => { node.remove(); if (opts.onDone) opts.onDone(); })
      .catch(() => node.remove());
}

function runFx(fx){
  for (const f of fx){
    if (f.kind === 'ownPlay' || f.kind === 'oppPlay'){
      const top = $('discard').lastElementChild;
      if (!top) continue;
      const el = cardEl(f.card);
      el.style.setProperty('--tilt', tiltOf(f.card.id) + 'deg');
      top.style.visibility = 'hidden';
      flyClone(el, f.from || rect($('draw-pile')), rect($('discard')),
               {onDone: () => { top.style.visibility = ''; }});
    } else if (f.kind === 'ownDraw'){
      const slot = document.querySelector('#hand .slot[data-cid="' + f.id + '"]');
      if (!slot) continue;
      slot.firstChild.style.visibility = 'hidden';
      flyClone(cardBackEl(), f.from, rect(slot),
               {delay:f.delay, onDone: () => { slot.firstChild.style.visibility = ''; }});
    } else if (f.kind === 'oppDraw'){
      const s = seatOf(f.player);
      if (!s) continue;
      for (let i = 0; i < Math.min(f.count, 4); i++)
        flyClone(cardBackEl(true), f.from, rect(s), {delay:i*90, dur:380});
    }
  }
}

function processEvents(events){
  if (!events.length) return;
  const still = snapshotMode || reducedMotion || events.some(e => e.type === 'game_started');
  const fx = [];
  for (const ev of events) apply(ev, still ? null : fx);
  render();
  if (!still) runFx(fx);
}

/* ---------- actions ---------- */
async function playCard(card){
  if (card.value === 'Wild' || card.value === 'Wild4'){
    pendingWild = card;
    $('color-modal').hidden = false;
    return;
  }
  const r = await api('/api/play?card_id=' + card.id, {method:'POST'});
  if (!r.ok) toast(r.error); else lastPlayedId = card.id;
}

document.querySelectorAll('#color-modal .wheel button').forEach(b => {
  b.onclick = async (e) => {
    e.stopPropagation();
    $('color-modal').hidden = true;
    if (!pendingWild) return;
    const id = pendingWild.id; pendingWild = null;
    const r = await api('/api/play?card_id=' + id + '&color=' + b.dataset.color, {method:'POST'});
    if (!r.ok) toast(r.error); else lastPlayedId = id;
  };
});
$('color-modal').onclick = (e) => {
  if (e.target === $('color-modal')){ $('color-modal').hidden = true; pendingWild = null; }
};

$('draw-pile').onclick = async () => {
  const r = await api('/api/draw', {method:'POST'}); if (!r.ok) toast(r.error);
};
$('pass-btn').onclick = async () => {
  const r = await api('/api/pass', {method:'POST'}); if (!r.ok) toast(r.error);
};
$('start-btn').onclick = async () => {
  const r = await api('/api/start', {method:'POST'}); if (!r.ok) toast(r.error);
};
$('win-back').onclick = () => { $('win-overlay').hidden = true; setView('lobby'); };
$('rules-btn').onclick = async () => {
  const r = await api('/api/rules', {method:'POST', body: $('rules-text').value});
  const s = $('rules-status');
  if (r.ok){ s.textContent = 'Rules accepted'; s.className = 'ok'; }
  else { s.textContent = r.error; s.className = 'err'; }
};

/* ---------- join / snapshot / polling ---------- */
async function refreshState(){
  const r = await api('/api/state');
  if (r.ok){ snapshotMode = true; processEvents(r.events); snapshotMode = false; }
}

async function joinAs(v){
  name = v;
  try {
    const r = await api('/api/join', {method:'POST'});
    if (!r.ok){
      $('join-err').textContent = r.error;
      name = null;
      sessionStorage.removeItem('uno-name');
      return;
    }
    sessionStorage.setItem('uno-name', v);
    setView('lobby');
    await refreshState();
    startPolling();
  } catch (e){ $('join-err').textContent = 'server unreachable'; name = null; }
}

$('join-btn').onclick = () => {
  const v = $('name-input').value.trim();
  if (v) joinAs(v);
};
$('name-input').addEventListener('keydown', e => { if (e.key === 'Enter') $('join-btn').click(); });

let polling = null;
function startPolling(){
  if (polling) return;
  polling = setInterval(async () => {
    try {
      const r = await api('/api/poll');
      if (r.ok) processEvents(r.events);
    } catch (e){ /* transient */ }
  }, 700);
}

let resizeT = null;
window.addEventListener('resize', () => {
  clearTimeout(resizeT);
  resizeT = setTimeout(() => { setFan(); layoutSeats(); }, 120);
});

$('rules-text').value = RULES_TEMPLATE;

const savedName = sessionStorage.getItem('uno-name');
if (savedName){
  $('name-input').value = savedName;
  joinAs(savedName);
}
</script>
</body>
</html>
|html}
;;
