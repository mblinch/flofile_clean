/**
 * FloFile Captions — website admin: Google sign-in + Tank01 roster editor
 * + roster jersey issues (with Google search).
 */
(function () {
  'use strict';

  var SPORTS = [
    { id: 'hockey', label: 'Hockey', league: 'NHL' },
    { id: 'baseball', label: 'Baseball', league: 'MLB' },
    { id: 'basketball', label: 'Basketball', league: 'NBA' },
    { id: 'wnba', label: 'WNBA', league: 'WNBA' },
    { id: 'soccer', label: 'Soccer', league: 'soccer' },
  ];

  var ROOT = 'sports_tank01';
  var state = {
    user: null,
    isAdmin: false,
    sportId: 'hockey',
    teams: [],
    teamId: null,
    players: [],
    issues: [],
    issuesSportId: '',
    panel: 'rosters', // rosters | issues
    busy: false,
  };

  var els = {};

  function $(id) {
    return document.getElementById(id);
  }

  function leagueForSport(sportId) {
    for (var i = 0; i < SPORTS.length; i++) {
      if (SPORTS[i].id === sportId) return SPORTS[i].league;
    }
    return sportId || 'sports';
  }

  function sportLabel(sportId) {
    for (var i = 0; i < SPORTS.length; i++) {
      if (SPORTS[i].id === sportId) return SPORTS[i].label;
    }
    return sportId;
  }

  function isAdminEmail(email) {
    if (!email) return false;
    var list = window.FLOFILE_ADMIN_EMAILS || [];
    var lower = String(email).trim().toLowerCase();
    for (var i = 0; i < list.length; i++) {
      if (String(list[i]).trim().toLowerCase() === lower) return true;
    }
    return false;
  }

  async function isAdminUser(user) {
    if (!user) return false;
    if (isAdminEmail(user.email)) return true;
    try {
      var token = await user.getIdTokenResult();
      var claim = token.claims && token.claims.admin;
      return claim === true || claim === 'true';
    } catch (_) {
      return false;
    }
  }

  function playerGoogleSearchUrl(sportId, fullName) {
    var league = leagueForSport(sportId);
    var name = (fullName || '').trim();
    var query = name ? league + ' player ' + name : league + ' player';
    return 'https://www.google.com/search?q=' + encodeURIComponent(query);
  }

  function openPlayerGoogleSearch(sportId, fullName) {
    window.open(
      playerGoogleSearchUrl(sportId, fullName),
      '_blank',
      'noopener,noreferrer'
    );
  }

  /** Clickable player name → Google search (`{league} player {name}`). */
  function playerGoogleLink(sportId, fullName, className) {
    var a = document.createElement('a');
    a.className = className || 'admin-player-link';
    a.href = playerGoogleSearchUrl(sportId, fullName);
    a.target = '_blank';
    a.rel = 'noopener noreferrer';
    a.textContent = (fullName || '').trim() || 'Player';
    a.title = 'Search Google for this player';
    return a;
  }

  function setStatus(msg, isError) {
    if (!els.status) return;
    els.status.textContent = msg || '';
    els.status.classList.toggle('is-error', !!isError);
  }

  function showPanel(name) {
    state.panel = name;
    if (els.panelRosters) {
      els.panelRosters.hidden = name !== 'rosters';
    }
    if (els.panelIssues) {
      els.panelIssues.hidden = name !== 'issues';
    }
    if (els.tabRosters) {
      els.tabRosters.classList.toggle('is-active', name === 'rosters');
    }
    if (els.tabIssues) {
      els.tabIssues.classList.toggle('is-active', name === 'issues');
    }
  }

  function renderAuth() {
    var signedOut = !state.user;
    var denied = !!state.user && !state.isAdmin;
    var ok = !!state.user && state.isAdmin;

    if (els.viewSignedOut) els.viewSignedOut.hidden = !signedOut;
    if (els.viewDenied) els.viewDenied.hidden = !denied;
    if (els.viewAdmin) els.viewAdmin.hidden = !ok;

    if (els.userChip) {
      if (ok) {
        els.userChip.hidden = false;
        els.userChip.textContent = state.user.email || 'Admin';
      } else {
        els.userChip.hidden = true;
      }
    }
    if (els.signOutBtn) els.signOutBtn.hidden = !state.user;
  }

  function fillSportSelect(selectEl, includeAll) {
    if (!selectEl) return;
    selectEl.innerHTML = '';
    if (includeAll) {
      var all = document.createElement('option');
      all.value = '';
      all.textContent = 'All sports';
      selectEl.appendChild(all);
    }
    for (var i = 0; i < SPORTS.length; i++) {
      var opt = document.createElement('option');
      opt.value = SPORTS[i].id;
      opt.textContent = SPORTS[i].label;
      selectEl.appendChild(opt);
    }
  }

  async function loadTeams() {
    var db = window.flofileDb;
    if (!db || !state.sportId) return;
    setStatus('Loading teams…');
    var snap = await db
      .collection(ROOT)
      .doc(state.sportId)
      .collection('teams')
      .get();
    var teams = [];
    snap.forEach(function (doc) {
      var data = doc.data() || {};
      var name = (data.displayName || data.name || doc.id || '').trim();
      teams.push({ id: doc.id, name: name || doc.id });
    });
    teams.sort(function (a, b) {
      return a.name.localeCompare(b.name);
    });
    state.teams = teams;
    if (
      !state.teamId ||
      !teams.some(function (t) {
        return t.id === state.teamId;
      })
    ) {
      state.teamId = teams.length ? teams[0].id : null;
    }
    renderTeamSelect();
    setStatus(teams.length ? teams.length + ' teams' : 'No teams found');
    await loadPlayers();
  }

  function renderTeamSelect() {
    if (!els.teamSelect) return;
    els.teamSelect.innerHTML = '';
    if (!state.teams.length) {
      var empty = document.createElement('option');
      empty.value = '';
      empty.textContent = 'No teams';
      els.teamSelect.appendChild(empty);
      return;
    }
    for (var i = 0; i < state.teams.length; i++) {
      var t = state.teams[i];
      var opt = document.createElement('option');
      opt.value = t.id;
      opt.textContent = t.name;
      if (t.id === state.teamId) opt.selected = true;
      els.teamSelect.appendChild(opt);
    }
  }

  async function loadPlayers() {
    var db = window.flofileDb;
    if (!db || !state.sportId || !state.teamId) {
      state.players = [];
      renderPlayers();
      return;
    }
    setStatus('Loading roster…');
    var snap = await db
      .collection(ROOT)
      .doc(state.sportId)
      .collection('teams')
      .doc(state.teamId)
      .collection('players')
      .get();
    var players = [];
    snap.forEach(function (doc) {
      var data = doc.data() || {};
      players.push({
        id: doc.id,
        fullName: (data.fullName || '').trim(),
        jerseyNumber: (data.jerseyNumber || '').trim(),
        position: (data.position || '').trim(),
        jerseySource: (data.jerseySource || '').trim(),
        playerId: (data.playerId || '').trim(),
      });
    });
    players.sort(function (a, b) {
      var aj = parseInt(a.jerseyNumber, 10);
      var bj = parseInt(b.jerseyNumber, 10);
      if (!isNaN(aj) && !isNaN(bj) && aj !== bj) return aj - bj;
      if (!isNaN(aj) && isNaN(bj)) return -1;
      if (isNaN(aj) && !isNaN(bj)) return 1;
      return a.fullName.localeCompare(b.fullName);
    });
    state.players = players;
    renderPlayers();
    setStatus(players.length + ' players');
  }

  function renderPlayers() {
    if (!els.playerTableBody) return;
    els.playerTableBody.innerHTML = '';
    if (!state.players.length) {
      var tr = document.createElement('tr');
      tr.innerHTML =
        '<td colspan="5" class="admin-empty">No players on this team.</td>';
      els.playerTableBody.appendChild(tr);
      return;
    }
    for (var i = 0; i < state.players.length; i++) {
      els.playerTableBody.appendChild(playerRow(state.players[i]));
    }
  }

  function playerRow(player) {
    var tr = document.createElement('tr');
    tr.dataset.id = player.id;

    var tdJersey = document.createElement('td');
    var inJersey = document.createElement('input');
    inJersey.type = 'text';
    inJersey.inputMode = 'numeric';
    inJersey.className = 'admin-input admin-input-narrow';
    inJersey.value = player.jerseyNumber;
    inJersey.setAttribute('aria-label', 'Jersey number');
    tdJersey.appendChild(inJersey);

    var tdName = document.createElement('td');
    var inName = document.createElement('input');
    inName.type = 'text';
    inName.className = 'admin-input';
    inName.value = player.fullName;
    inName.setAttribute('aria-label', 'Full name');
    tdName.appendChild(inName);

    var tdPos = document.createElement('td');
    var inPos = document.createElement('input');
    inPos.type = 'text';
    inPos.className = 'admin-input admin-input-narrow';
    inPos.value = player.position;
    inPos.setAttribute('aria-label', 'Position');
    tdPos.appendChild(inPos);

    var tdSrc = document.createElement('td');
    tdSrc.className = 'admin-muted';
    tdSrc.textContent = player.jerseySource || '—';

    var tdActions = document.createElement('td');
    tdActions.className = 'admin-actions';
    var saveBtn = document.createElement('button');
    saveBtn.type = 'button';
    saveBtn.className = 'btn btn-secondary btn-sm';
    saveBtn.textContent = 'Save';
    saveBtn.addEventListener('click', function () {
      savePlayer(player.id, inName.value, inJersey.value, inPos.value);
    });
    var googleBtn = document.createElement('button');
    googleBtn.type = 'button';
    googleBtn.className = 'btn btn-ghost btn-sm';
    googleBtn.textContent = 'Google';
    googleBtn.addEventListener('click', function () {
      openPlayerGoogleSearch(state.sportId, inName.value || player.fullName);
    });
    var delBtn = document.createElement('button');
    delBtn.type = 'button';
    delBtn.className = 'btn btn-danger-ghost btn-sm';
    delBtn.textContent = 'Delete';
    delBtn.addEventListener('click', function () {
      deletePlayer(player.id, player.fullName);
    });
    tdActions.appendChild(saveBtn);
    tdActions.appendChild(googleBtn);
    tdActions.appendChild(delBtn);

    tr.appendChild(tdJersey);
    tr.appendChild(tdName);
    tr.appendChild(tdPos);
    tr.appendChild(tdSrc);
    tr.appendChild(tdActions);
    return tr;
  }

  async function savePlayer(playerId, fullName, jerseyNumber, position) {
    var db = window.flofileDb;
    if (!db || !state.sportId || !state.teamId) return;
    var name = (fullName || '').trim();
    var jersey = (jerseyNumber || '').trim();
    var pos = (position || '').trim();
    if (!name) {
      setStatus('Name is required.', true);
      return;
    }
    if (jersey && isNaN(parseInt(jersey, 10))) {
      setStatus('Jersey must be numeric.', true);
      return;
    }
    try {
      setStatus('Saving…');
      var ref = db
        .collection(ROOT)
        .doc(state.sportId)
        .collection('teams')
        .doc(state.teamId)
        .collection('players')
        .doc(playerId);
      var snap = await ref.get();
      var cur = (snap.exists && snap.data()) || {};
      var oldJersey = (cur.jerseyNumber || '').trim();
      var oldSource = (cur.jerseySource || '').trim();
      var existingTank = (cur.tank01JerseyNumber || '').trim();
      var payload = {
        fullName: name,
        position: pos,
        updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
      };
      if (jersey) {
        payload.jerseyNumber = jersey;
        payload.displayName = name + ' #' + jersey;
        payload.jerseySource = 'manual';
        var knownTank = existingTank
          ? existingTank
          : oldSource !== 'manual' && oldJersey
            ? oldJersey
            : '';
        if (knownTank && knownTank !== jersey) {
          payload.tank01JerseyNumber = knownTank;
        } else {
          payload.tank01JerseyNumber =
            firebase.firestore.FieldValue.delete();
        }
      } else {
        payload.jerseyNumber = '';
        payload.displayName = name;
        payload.tank01JerseyNumber =
          firebase.firestore.FieldValue.delete();
      }
      await ref.set(payload, { merge: true });
      setStatus('Saved ' + name);
      await loadPlayers();
    } catch (e) {
      setStatus(String(e.message || e), true);
    }
  }

  async function deletePlayer(playerId, fullName) {
    if (
      !window.confirm(
        'Delete “' + (fullName || playerId) + '” from this roster?'
      )
    ) {
      return;
    }
    var db = window.flofileDb;
    if (!db || !state.sportId || !state.teamId) return;
    try {
      setStatus('Deleting…');
      await db
        .collection(ROOT)
        .doc(state.sportId)
        .collection('teams')
        .doc(state.teamId)
        .collection('players')
        .doc(playerId)
        .delete();
      setStatus('Deleted');
      await loadPlayers();
    } catch (e) {
      setStatus(String(e.message || e), true);
    }
  }

  async function addPlayer() {
    var db = window.flofileDb;
    if (!db || !state.sportId || !state.teamId) return;
    var name = window.prompt('Full name');
    if (name == null) return;
    name = name.trim();
    if (!name) return;
    var jersey = (window.prompt('Jersey number (optional)') || '').trim();
    if (jersey && isNaN(parseInt(jersey, 10))) {
      setStatus('Jersey must be numeric.', true);
      return;
    }
    try {
      setStatus('Adding…');
      var slug = name
        .toLowerCase()
        .replace(/[^a-z0-9]+/g, '_')
        .replace(/^_|_$/g, '');
      var id = 'manual_' + slug + '_' + Date.now().toString(36);
      var payload = {
        fullName: name,
        firstName: name.split(/\s+/)[0] || name,
        position: '',
        playerId: id,
        jerseySource: jersey ? 'manual' : '',
        displayName: jersey ? name + ' #' + jersey : name,
        jerseyNumber: jersey || '',
        updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
      };
      await db
        .collection(ROOT)
        .doc(state.sportId)
        .collection('teams')
        .doc(state.teamId)
        .collection('players')
        .doc(id)
        .set(payload);
      setStatus('Added ' + name);
      await loadPlayers();
    } catch (e) {
      setStatus(String(e.message || e), true);
    }
  }

  function kindOrder(kind) {
    if (kind === 'missing') return 0;
    if (kind === 'duplicate') return 1;
    if (kind === 'differs') return 2;
    return 9;
  }

  function jerseyKey(value) {
    return String(value || '')
      .trim()
      .replace(/^0+/, '') || String(value || '').trim();
  }

  async function scanIssues() {
    var db = window.flofileDb;
    if (!db) return;
    var sportFilter = (els.issuesSportSelect && els.issuesSportSelect.value) || '';
    state.issuesSportId = sportFilter;
    var sports = sportFilter
      ? SPORTS.filter(function (s) {
          return s.id === sportFilter;
        })
      : SPORTS.slice();
    setStatus('Scanning jersey issues…');
    state.busy = true;
    var issues = [];
    try {
      for (var s = 0; s < sports.length; s++) {
        var sport = sports[s];
        var teamsSnap = await db
          .collection(ROOT)
          .doc(sport.id)
          .collection('teams')
          .get();
        for (var t = 0; t < teamsSnap.docs.length; t++) {
          var teamDoc = teamsSnap.docs[t];
          var teamData = teamDoc.data() || {};
          var teamName = (teamData.displayName || teamData.name || teamDoc.id).trim();
          var playersSnap = await teamDoc.ref.collection('players').get();
          var byJersey = {};
          playersSnap.forEach(function (pDoc) {
            var data = pDoc.data() || {};
            var fullName = (data.fullName || '').trim();
            if (!fullName) return;
            var jersey = (data.jerseyNumber || '').trim();
            var tankJersey = (data.tank01JerseyNumber || '').trim();
            var source = (data.jerseySource || '').trim();
            var row = {
              kind: '',
              sportId: sport.id,
              teamId: teamDoc.id,
              teamName: teamName,
              playerDocId: pDoc.id,
              fullName: fullName,
              jerseyNumber: jersey,
              tank01JerseyNumber: tankJersey,
              position: (data.position || '').trim(),
              detail: null,
            };
            if (!jersey) {
              row.kind = 'missing';
              issues.push(row);
              return;
            }
            if (source === 'manual' && tankJersey && tankJersey !== jersey) {
              issues.push({
                kind: 'differs',
                sportId: sport.id,
                teamId: teamDoc.id,
                teamName: teamName,
                playerDocId: pDoc.id,
                fullName: fullName,
                jerseyNumber: jersey,
                tank01JerseyNumber: tankJersey,
                position: row.position,
                detail: 'Saved #' + jersey + ' · Tank01 has #' + tankJersey,
              });
            }
            var key = jerseyKey(jersey);
            if (!byJersey[key]) byJersey[key] = [];
            byJersey[key].push(row);
          });
          Object.keys(byJersey).forEach(function (key) {
            var group = byJersey[key];
            if (group.length < 2) return;
            for (var i = 0; i < group.length; i++) {
              var others = group
                .filter(function (_, idx) {
                  return idx !== i;
                })
                .map(function (r) {
                  return r.fullName;
                });
              issues.push({
                kind: 'duplicate',
                sportId: group[i].sportId,
                teamId: group[i].teamId,
                teamName: group[i].teamName,
                playerDocId: group[i].playerDocId,
                fullName: group[i].fullName,
                jerseyNumber: group[i].jerseyNumber,
                position: group[i].position,
                alsoWornBy: others,
                detail: others.length
                  ? 'Also worn by ' + others.join(', ')
                  : null,
              });
            }
          });
        }
      }
      issues.sort(function (a, b) {
        var s = a.sportId.localeCompare(b.sportId);
        if (s) return s;
        var tn = a.teamName.localeCompare(b.teamName);
        if (tn) return tn;
        var ka = kindOrder(a.kind);
        var kb = kindOrder(b.kind);
        if (ka !== kb) return ka - kb;
        var j = (a.jerseyNumber || '').localeCompare(b.jerseyNumber || '');
        if (j) return j;
        return a.fullName.localeCompare(b.fullName);
      });
      state.issues = issues;
      renderIssues();
      var missing = 0;
      var duplicates = 0;
      var differs = 0;
      for (var i = 0; i < issues.length; i++) {
        if (issues[i].kind === 'missing') missing++;
        else if (issues[i].kind === 'duplicate') duplicates++;
        else if (issues[i].kind === 'differs') differs++;
      }
      if (!issues.length) {
        setStatus('No missing, duplicate, or manual-vs-Tank01 jerseys.');
      } else {
        var parts = [];
        if (missing) parts.push(missing + ' missing');
        if (duplicates) parts.push(duplicates + ' duplicate');
        if (differs) parts.push(differs + ' vs Tank01');
        setStatus(
          'Found ' + issues.length + ' issue(s): ' + parts.join(', ') + '.'
        );
      }
    } catch (e) {
      setStatus(String(e.message || e), true);
    } finally {
      state.busy = false;
    }
  }

  function renderIssues() {
    if (!els.issuesList) return;
    els.issuesList.innerHTML = '';
    if (!state.issues.length) {
      els.issuesList.innerHTML =
        '<p class="admin-empty glow">Run a scan to list missing, duplicate, and manual-vs-Tank01 jersey numbers.</p>';
      return;
    }
    var bySport = {};
    for (var i = 0; i < state.issues.length; i++) {
      var issue = state.issues[i];
      if (!bySport[issue.sportId]) bySport[issue.sportId] = [];
      bySport[issue.sportId].push(issue);
    }
    Object.keys(bySport)
      .sort()
      .forEach(function (sportId) {
        var block = document.createElement('section');
        block.className = 'admin-issue-block';
        var h = document.createElement('h3');
        h.textContent =
          sportLabel(sportId) + ' · ' + bySport[sportId].length + ' issue(s)';
        block.appendChild(h);
        var list = document.createElement('div');
        list.className = 'admin-issue-rows';
        bySport[sportId].forEach(function (row) {
          list.appendChild(issueRow(row));
        });
        block.appendChild(list);
        els.issuesList.appendChild(block);
      });
  }

  function issueRow(issue) {
    var row = document.createElement('div');
    row.className = 'admin-issue-row';

    var main = document.createElement('div');
    main.className = 'admin-issue-main';
    var title = document.createElement('div');
    title.className = 'admin-issue-title';
    title.appendChild(playerGoogleLink(issue.sportId, issue.fullName));
    if (issue.position) {
      title.appendChild(document.createTextNode(' · ' + issue.position));
    }
    var sub = document.createElement('div');
    sub.className = 'admin-issue-sub';
    var kindLabel =
      issue.kind === 'missing'
        ? 'Missing jersey'
        : issue.kind === 'differs'
          ? issue.jerseyNumber && issue.tank01JerseyNumber
            ? 'Saved #' +
              issue.jerseyNumber +
              ' · Tank01 #' +
              issue.tank01JerseyNumber
            : 'Differs from Tank01'
          : issue.jerseyNumber
            ? 'Duplicate #' + issue.jerseyNumber
            : 'Duplicate jersey';
    sub.appendChild(document.createTextNode(issue.teamName + ' · ' + kindLabel));
    var also = issue.alsoWornBy || [];
    if (also.length) {
      sub.appendChild(document.createTextNode(' · Also worn by '));
      for (var i = 0; i < also.length; i++) {
        if (i) sub.appendChild(document.createTextNode(', '));
        sub.appendChild(
          playerGoogleLink(issue.sportId, also[i], 'admin-player-link admin-player-link-inline')
        );
      }
    }
    main.appendChild(title);
    main.appendChild(sub);

    var actions = document.createElement('div');
    actions.className = 'admin-actions';
    var googleBtn = document.createElement('button');
    googleBtn.type = 'button';
    googleBtn.className = 'btn btn-ghost btn-sm';
    googleBtn.textContent = 'Google';
    googleBtn.addEventListener('click', function () {
      openPlayerGoogleSearch(issue.sportId, issue.fullName);
    });
    var setBtn = document.createElement('button');
    setBtn.type = 'button';
    setBtn.className = 'btn btn-secondary btn-sm';
    setBtn.textContent = 'Set #';
    setBtn.addEventListener('click', function () {
      setIssueJersey(issue);
    });
    actions.appendChild(googleBtn);
    actions.appendChild(setBtn);

    row.appendChild(main);
    row.appendChild(actions);
    return row;
  }

  async function setIssueJersey(issue) {
    var db = window.flofileDb;
    if (!db) return;
    var next = window.prompt(
      'Jersey number for ' + issue.fullName,
      issue.jerseyNumber || ''
    );
    if (next == null) return;
    next = next.trim();
    if (!next || isNaN(parseInt(next, 10))) {
      setStatus('Jersey must be a number.', true);
      return;
    }
    try {
      setStatus('Saving…');
      var ref = db
        .collection(ROOT)
        .doc(issue.sportId)
        .collection('teams')
        .doc(issue.teamId)
        .collection('players')
        .doc(issue.playerDocId);
      var snap = await ref.get();
      var data = (snap.exists && snap.data()) || {};
      var oldJersey = (data.jerseyNumber || '').trim();
      var oldSource = (data.jerseySource || '').trim();
      var existingTank = (data.tank01JerseyNumber || '').trim();
      var issueTank = (issue.tank01JerseyNumber || '').trim();
      var knownTank = existingTank
        ? existingTank
        : issueTank
          ? issueTank
          : oldSource !== 'manual' && oldJersey
            ? oldJersey
            : '';
      var payload = {
        jerseyNumber: next,
        displayName: issue.fullName + ' #' + next,
        jerseySource: 'manual',
        updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
      };
      if (knownTank && knownTank !== next) {
        payload.tank01JerseyNumber = knownTank;
      } else {
        payload.tank01JerseyNumber =
          firebase.firestore.FieldValue.delete();
      }
      await ref.set(payload, { merge: true });
      setStatus('Saved #' + next + ' for ' + issue.fullName);
      await scanIssues();
    } catch (e) {
      setStatus(String(e.message || e), true);
    }
  }

  async function signIn() {
    try {
      setStatus('Signing in…');
      var provider = new firebase.auth.GoogleAuthProvider();
      provider.setCustomParameters({ prompt: 'select_account' });
      await firebase.auth().signInWithPopup(provider);
    } catch (e) {
      setStatus(String(e.message || e), true);
    }
  }

  async function signOut() {
    try {
      await firebase.auth().signOut();
      setStatus('');
    } catch (e) {
      setStatus(String(e.message || e), true);
    }
  }

  async function onAuth(user) {
    state.user = user;
    state.isAdmin = user ? await isAdminUser(user) : false;
    renderAuth();
    if (state.isAdmin) {
      showPanel(state.panel || 'rosters');
      if (els.sportSelect) els.sportSelect.value = state.sportId;
      await loadTeams();
    }
  }

  function bind() {
    els.viewSignedOut = $('view-signed-out');
    els.viewDenied = $('view-denied');
    els.viewAdmin = $('view-admin');
    els.userChip = $('admin-user-chip');
    els.signOutBtn = $('admin-sign-out');
    els.status = $('admin-status');
    els.panelRosters = $('panel-rosters');
    els.panelIssues = $('panel-issues');
    els.tabRosters = $('tab-rosters');
    els.tabIssues = $('tab-issues');
    els.sportSelect = $('sport-select');
    els.teamSelect = $('team-select');
    els.playerTableBody = $('player-table-body');
    els.issuesSportSelect = $('issues-sport-select');
    els.issuesList = $('issues-list');

    fillSportSelect(els.sportSelect, false);
    fillSportSelect(els.issuesSportSelect, true);

    var signInBtn = $('admin-sign-in');
    if (signInBtn) signInBtn.addEventListener('click', signIn);
    if (els.signOutBtn) els.signOutBtn.addEventListener('click', signOut);

    if (els.tabRosters) {
      els.tabRosters.addEventListener('click', function () {
        showPanel('rosters');
      });
    }
    if (els.tabIssues) {
      els.tabIssues.addEventListener('click', function () {
        showPanel('issues');
      });
    }
    if (els.sportSelect) {
      els.sportSelect.addEventListener('change', function () {
        state.sportId = els.sportSelect.value;
        state.teamId = null;
        loadTeams();
      });
    }
    if (els.teamSelect) {
      els.teamSelect.addEventListener('change', function () {
        state.teamId = els.teamSelect.value || null;
        loadPlayers();
      });
    }
    var addBtn = $('add-player');
    if (addBtn) addBtn.addEventListener('click', addPlayer);
    var reloadBtn = $('reload-roster');
    if (reloadBtn) reloadBtn.addEventListener('click', loadPlayers);
    var scanBtn = $('scan-issues');
    if (scanBtn) scanBtn.addEventListener('click', scanIssues);
  }

  function boot() {
    bind();
    if (!window.FLOFILE_FIREBASE) {
      setStatus('Missing Firebase config.', true);
      return;
    }
    if (!firebase.apps.length) {
      firebase.initializeApp(window.FLOFILE_FIREBASE);
    }
    window.flofileDb = firebase.firestore();
    firebase.auth().onAuthStateChanged(function (user) {
      onAuth(user);
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot);
  } else {
    boot();
  }
})();
