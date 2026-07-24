
(function () {
    'use strict';

    const $ = (sel) => document.querySelector(sel);
    const tablet      = $('#tablet');
    const tabletFrame = $('#tabletFrame');
    const callPopup   = $('#callPopup');
    const callContent = $('#callContent');
    const callCounter = $('#callCounter');
    const callNav     = $('#callNav');


    var tabletURL = '';
    var dimmerEnabled = false;

    var RESOURCE = (typeof GetParentResourceName === 'function')
        ? GetParentResourceName()
        : 'cad-tablet';

    function nuiPost(action) {
        return fetch('https://' + RESOURCE + '/' + action, {
            method: 'POST',
            body: '{}'
        }).catch(function () {});
    }

    function bust(url) {
        if (!url) return url;
        var sep = url.indexOf('?') === -1 ? '?' : '&';
        return url + sep + 'fivem=1&_cb=' + Date.now();
    }

    var unloadAfterMs = 300 * 1000;
    var parkTimer = null;

    function postToTablet(type) {
        try {
            if (tabletFrame.contentWindow && tabletURL) {
                tabletFrame.contentWindow.postMessage({ type: type }, '*');
            }
        } catch (e) {  }
    }

    function scheduleParking() {
        if (parkTimer) clearTimeout(parkTimer);
        if (!unloadAfterMs) return;
        parkTimer = setTimeout(function () {
            parkTimer = null;
            tabletURL = null;
            tabletFrame.src = 'about:blank';
        }, unloadAfterMs);
    }

    var overlay        = $('#tabletOverlay');
    var overlayText    = $('#tabletOverlayText');
    var overlayRetry   = $('#tabletOverlayRetry');
    var readyReceived  = false;
    var loadFired      = false;
    var watchdogTimer  = null;
    var graceTimer     = null;
    var reloadAttempts = 0;
    var lastLoadFailed = false;
    var READY_TIMEOUT_MS = 15000;
    var LOAD_GRACE_MS    = 6000;
    var MAX_AUTO_RELOADS = 3;

    function showOverlay(text, showRetry) {
        if (overlayText) overlayText.textContent = text;
        if (overlayRetry) overlayRetry.classList[showRetry ? 'remove' : 'add']('hidden');
        if (overlay) overlay.classList.remove('hidden');
    }
    function hideOverlay() {
        if (overlay) overlay.classList.add('hidden');
        if (overlayRetry) overlayRetry.classList.add('hidden');
    }
    function clearWatchdogs() {
        if (watchdogTimer) { clearTimeout(watchdogTimer); watchdogTimer = null; }
        if (graceTimer)    { clearTimeout(graceTimer);    graceTimer = null; }
    }

    function onWatchdog() {
        watchdogTimer = null;
        if (readyReceived || loadFired) return;
        if (reloadAttempts < MAX_AUTO_RELOADS) {
            reloadAttempts++;
            showOverlay('Reconnecting… (' + reloadAttempts + ')', false);
            loadIframe(tabletURL, false);
        } else {
            lastLoadFailed = true;
            showOverlay('Could not load the tablet.', true);
        }
    }

    function loadIframe(url, resetAttempts) {
        if (!url) return;
        if (resetAttempts) reloadAttempts = 0;
        lastLoadFailed = false;
        tabletURL = url;
        readyReceived = false;
        loadFired = false;
        clearWatchdogs();
        showOverlay(reloadAttempts > 0 ? 'Reconnecting… (' + reloadAttempts + ')' : 'Loading CDECAD…', false);
        tabletFrame.src = bust(url);
        watchdogTimer = setTimeout(onWatchdog, READY_TIMEOUT_MS);
    }

    tabletFrame.addEventListener('load', function () {
        if (!tabletURL) return;
        loadFired = true;
        if (readyReceived) return;
        if (graceTimer) clearTimeout(graceTimer);
        graceTimer = setTimeout(function () {
            graceTimer = null;
            if (!readyReceived) hideOverlay();
        }, LOAD_GRACE_MS);
    });

    if (overlayRetry) {
        overlayRetry.addEventListener('click', function () {
            loadIframe(tabletURL || '', true);
        });
    }

    function openTablet(url, dimmer, unloadAfter) {
        if (unloadAfter !== undefined && unloadAfter !== null) {
            unloadAfterMs = Math.max(0, Number(unloadAfter) || 0) * 1000;
        }
        if (parkTimer) { clearTimeout(parkTimer); parkTimer = null; }
        if (tabletURL !== url || lastLoadFailed) {
            loadIframe(url, true);
        }
        dimmerEnabled = !!dimmer;
        tablet.classList.remove('hidden');
        tablet.classList.remove('dimmed');
        postToTablet('cde:tablet-visible');
    }

    function closeTablet() {
        nuiPost('closeTablet');
        tablet.classList.add('hidden');
        clearWatchdogs();
        hideOverlay();
        postToTablet('cde:tablet-hidden');
        scheduleParking();
    }

    $('#closeTablet').addEventListener('click', closeTablet);

    window.addEventListener('keydown', function (e) {
        if (e.key === 'Escape' && !tablet.classList.contains('hidden')) {
            e.preventDefault();
            e.stopPropagation();
            closeTablet();
        }
    }, true);

    var LKEY = 'cde-tablet-layout';
    var tabletLayout = null;
    try { tabletLayout = JSON.parse(localStorage.getItem(LKEY) || 'null'); } catch (e) { tabletLayout = null; }

    var frameEl = document.querySelector('.tablet-frame');

    var MIN_W = 480, MIN_H = 360;

    function clampLayout(l) {
        var maxW = Math.max(MIN_W, window.innerWidth - 20);
        var maxH = Math.max(MIN_H, window.innerHeight - 20);
        l.w = Math.min(maxW, Math.max(MIN_W, l.w));
        l.h = Math.min(maxH, Math.max(MIN_H, l.h));
        l.x = Math.min(window.innerWidth - 80, Math.max(10 - l.w + 80, l.x));
        l.y = Math.min(window.innerHeight - 50, Math.max(0, l.y));
        return l;
    }

    function applyTabletLayout() {
        if (!tabletLayout) {
            tablet.classList.remove('custom');
            tablet.style.transform = '';
            tablet.style.left = '';
            tablet.style.top = '';
            frameEl.style.width = '';
            frameEl.style.height = '';
            return;
        }
        clampLayout(tabletLayout);
        tablet.classList.add('custom');
        tablet.style.transform = 'none';
        tablet.style.left = tabletLayout.x + 'px';
        tablet.style.top = tabletLayout.y + 'px';
        frameEl.style.width = tabletLayout.w + 'px';
        frameEl.style.height = tabletLayout.h + 'px';
    }
    applyTabletLayout();

    function currentLayout() {
        var r = frameEl.getBoundingClientRect();
        return { x: r.left, y: r.top, w: r.width, h: r.height };
    }

    function saveLayout() {
        try { if (tabletLayout) localStorage.setItem(LKEY, JSON.stringify(tabletLayout)); } catch (e) {  }
    }

    var tabletDrag = null;

    var headerEl = document.getElementById('tabletHeader') || document.querySelector('.tablet-header');
    if (headerEl) {
        headerEl.style.cursor = 'move';
        headerEl.style.userSelect = 'none';
    }

    var resizeEl = document.getElementById('tabletResize');
    if (!resizeEl && frameEl) {
        resizeEl = document.createElement('div');
        resizeEl.id = 'tabletResize';
        resizeEl.title = 'Drag to resize';
        var rs = resizeEl.style;
        rs.position = 'absolute';
        rs.right = '0';
        rs.bottom = '0';
        rs.width = '22px';
        rs.height = '22px';
        rs.cursor = 'nwse-resize';
        rs.zIndex = '3';
        rs.pointerEvents = 'auto';
        rs.opacity = '0.55';
        rs.background = 'linear-gradient(135deg, transparent 0 55%, #3b82f6 55% 62%, transparent 62% 72%, #3b82f6 72% 79%, transparent 79%)';
        frameEl.style.position = 'relative';
        frameEl.appendChild(resizeEl);
    }

    var hintEl = document.getElementById('tabletHint');
    if (!hintEl && headerEl) {
        hintEl = document.createElement('span');
        hintEl.id = 'tabletHint';
        var hs = hintEl.style;
        hs.display = 'none';
        hs.color = '#93a6b8';
        hs.fontSize = '11px';
        hs.margin = '0 12px';
        hs.whiteSpace = 'nowrap';
        hs.overflow = 'hidden';
        hs.textOverflow = 'ellipsis';
        hintEl.innerHTML = 'Drag this bar to move &middot; drag the corner to resize &middot; /tabletreset restores the default';
        var closeBtn = document.getElementById('closeTablet');
        if (closeBtn && closeBtn.parentNode === headerEl) {
            headerEl.insertBefore(hintEl, closeBtn);
        } else {
            headerEl.appendChild(hintEl);
        }
    }

    function setDragging(on) {
        tablet.classList[on ? 'add' : 'remove']('dragging');
        tabletFrame.style.pointerEvents = on ? 'none' : '';
    }

    if (headerEl) headerEl.addEventListener('mousedown', function (e) {
        if (e.target && e.target.id === 'closeTablet') return;
        var p = currentLayout();
        tabletDrag = { kind: 'move', sx: e.clientX, sy: e.clientY, x: p.x, y: p.y, w: p.w, h: p.h };
        setDragging(true);
        e.preventDefault();
    });
    if (resizeEl) resizeEl.addEventListener('mousedown', function (e) {
        var p = currentLayout();
        tabletDrag = { kind: 'size', sx: e.clientX, sy: e.clientY, x: p.x, y: p.y, w: p.w, h: p.h };
        setDragging(true);
        e.preventDefault();
        e.stopPropagation();
    });
    window.addEventListener('mousemove', function (e) {
        if (!tabletDrag) return;
        if (tabletDrag.kind === 'move') {
            tabletLayout = clampLayout({
                x: tabletDrag.x + (e.clientX - tabletDrag.sx),
                y: tabletDrag.y + (e.clientY - tabletDrag.sy),
                w: tabletDrag.w, h: tabletDrag.h
            });
        } else {
            tabletLayout = clampLayout({
                x: tabletDrag.x, y: tabletDrag.y,
                w: tabletDrag.w + (e.clientX - tabletDrag.sx),
                h: tabletDrag.h + (e.clientY - tabletDrag.sy)
            });
        }
        applyTabletLayout();
    });
    window.addEventListener('mouseup', function () {
        if (!tabletDrag) return;
        tabletDrag = null;
        setDragging(false);
        saveLayout();
    });

    var hintTimer = null;
    function showMoveHint() {
        tablet.classList.add('hinting');
        if (hintEl) hintEl.style.display = 'inline';
        if (hintTimer) clearTimeout(hintTimer);
        hintTimer = setTimeout(function () {
            tablet.classList.remove('hinting');
            if (hintEl) hintEl.style.display = 'none';
        }, 6000);
    }

    function resetTabletLayout() {
        tabletLayout = null;
        try { localStorage.removeItem(LKEY); } catch (e) {  }
        applyTabletLayout();
    }

    tablet.addEventListener('mouseenter', function () {
        if (dimmerEnabled) tablet.classList.remove('dimmed');
    });
    tablet.addEventListener('mouseleave', function () {
        if (dimmerEnabled && !tablet.classList.contains('hidden')) {
            tablet.classList.add('dimmed');
        }
    });


    const priorityClass = {
        low: 'priority-low',
        normal: 'priority-normal',
        medium: 'priority-medium',
        high: 'priority-high',
        critical: 'priority-critical',
    };

    const statusClass = {
        pending: 'status-pending',
        assigned: 'status-assigned',
        enroute: 'status-enroute',
        'on-scene': 'status-on-scene',
    };

    function renderCall(call) {
        if (!call) {
            callContent.innerHTML = '<div class="no-calls">No active calls</div>';
            return;
        }

        callContent.innerHTML = [
            field('Call Code', call.callType, 'call-type'),
            '<div class="call-row">'
                + field('Status', '<span class="status-badge ' + (statusClass[call.status] || '') + '">' + esc(call.status) + '</span>', '', true)
                + field('Priority', '<span class="priority-badge ' + (priorityClass[call.priority] || 'priority-normal') + '">' + esc(call.priority) + '</span>', '', true)
            + '</div>',
            field('Location', call.location + (call.postal ? ' (Postal: ' + esc(call.postal) + ')' : '')),
            call.description ? field('Description', call.description) : '',
            field('Incident #', call.id),
        ].join('');
    }

    function field(label, value, extraClass, isHtml) {
        return '<div class="call-field">'
            + '<div class="call-label">' + esc(label) + '</div>'
            + '<div class="call-value ' + (extraClass || '') + '">' + (isHtml ? value : esc(value)) + '</div>'
            + '</div>';
    }

    function esc(str) {
        if (str == null) return '';
        var d = document.createElement('div');
        d.textContent = String(str);
        return d.innerHTML;
    }

    $('#prevCall').addEventListener('click', function () { nuiPost('prevCall'); });
    $('#nextCall').addEventListener('click', function () { nuiPost('nextCall'); });


    window.addEventListener('message', function (event) {
        var data = event.data;
        if (!data || !data.type) return;

        switch (data.type) {
            case 'cde:cad-ready':
                readyReceived = true;
                reloadAttempts = 0;
                clearWatchdogs();
                hideOverlay();
                break;

            case 'openTablet':
                openTablet(data.url, data.dimmer, data.unloadAfter);
                break;

            case 'closeTablet':
                tablet.classList.add('hidden');
                clearWatchdogs();
                hideOverlay();
                postToTablet('cde:tablet-hidden');
                scheduleParking();
                break;

            case 'reloadTablet':
                if (tabletURL) {
                    loadIframe(tabletURL, true);
                }
                break;

            case 'tabletMoveHint':
                showMoveHint();
                break;

            case 'tabletResetLayout':
                resetTabletLayout();
                break;

            case 'showPopup':
                callPopup.classList.remove('hidden');
                break;

            case 'hidePopup':
                callPopup.classList.add('hidden');
                break;

            case 'updateCalls':
                var calls = data.calls || [];
                var idx   = (data.callIndex || 1) - 1;
                var total = data.totalCalls || 0;

                callCounter.textContent = total > 0 ? (idx + 1) + ' / ' + total : '0 / 0';

                if (total > 0 && calls[idx]) {
                    renderCall(calls[idx]);
                } else {
                    callContent.innerHTML = '<div class="no-calls">No active calls</div>';
                }

                if (total > 1) {
                    callNav.classList.remove('hidden');
                } else {
                    callNav.classList.add('hidden');
                }
                break;
        }
    });
})();
