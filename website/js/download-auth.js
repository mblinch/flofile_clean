/**
 * FloFile Captions — download page: Google sign-in unlocks Mac zip link.
 */
(function () {
  'use strict';

  var state = { user: null };
  var els = {};

  function $(id) {
    return document.getElementById(id);
  }

  function setStatus(msg, isError) {
    if (!els.status) return;
    els.status.textContent = msg || '';
    els.status.classList.toggle('is-error', !!isError);
  }

  function downloadMeta() {
    return window.FLOFILE_MAC_DOWNLOAD || {};
  }

  function render() {
    var signedIn = !!state.user;
    if (els.viewSignedOut) els.viewSignedOut.hidden = signedIn;
    if (els.viewSignedIn) els.viewSignedIn.hidden = !signedIn;
    if (els.signOutBtn) els.signOutBtn.hidden = !signedIn;
    if (els.userChip) {
      if (signedIn) {
        els.userChip.hidden = false;
        els.userChip.textContent = state.user.email || 'Signed in';
      } else {
        els.userChip.hidden = true;
      }
    }

    var meta = downloadMeta();
    if (els.downloadBtn && meta.url) {
      els.downloadBtn.href = meta.url;
      els.downloadBtn.setAttribute(
        'download',
        'FloFileBeta.zip'
      );
    }
    if (els.versionLabel) {
      els.versionLabel.textContent =
        meta.label || (meta.version ? 'Version ' + meta.version : 'macOS build');
    }
  }

  async function signIn() {
    try {
      setStatus('Signing in…');
      var provider = new firebase.auth.GoogleAuthProvider();
      provider.setCustomParameters({ prompt: 'select_account' });
      await firebase.auth().signInWithPopup(provider);
      setStatus('');
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

  function bind() {
    els.viewSignedOut = $('download-signed-out');
    els.viewSignedIn = $('download-signed-in');
    els.userChip = $('download-user-chip');
    els.signOutBtn = $('download-sign-out');
    els.status = $('download-status');
    els.downloadBtn = $('mac-download-btn');
    els.versionLabel = $('mac-download-version');

    var signInBtn = $('download-sign-in');
    if (signInBtn) signInBtn.addEventListener('click', signIn);
    if (els.signOutBtn) els.signOutBtn.addEventListener('click', signOut);
  }

  function boot() {
    bind();
    if (!window.FLOFILE_FIREBASE) {
      setStatus('Missing Firebase config.', true);
      return;
    }
    if (typeof firebase === 'undefined') {
      setStatus('Firebase failed to load.', true);
      return;
    }
    if (!firebase.apps.length) {
      firebase.initializeApp(window.FLOFILE_FIREBASE);
    }
    firebase.auth().onAuthStateChanged(function (user) {
      state.user = user;
      render();
    });
    render();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot);
  } else {
    boot();
  }
})();
