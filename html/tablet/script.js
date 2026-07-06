(function () {
    'use strict';

    const $ = (sel) => document.querySelector(sel);
    const tablet      = $('#tablet');
    const tabletFrame = $('#tabletFrame');
    const callPopup   = $('#callPopup');
    const callContent = $('#callContent');
    const callCounter = $('#callCounter');
    const callNav     = $('#callNav');

    // ─── Tablet ──────────────────────────────────────────────────────────────

    var tabletURL = '';
    var dimmerEnabled = false;

    // GetParentResourceName is injected by FiveM's NUI runtime.
    var RESOURCE = (typeof GetParentResourceName === 'function')
        ? GetParentResourceName()
        : 'cad-tablet';

    function nuiPost(action) {
        // Omit Content-Type; some FXServer versions reject it with an empty body.
        return fetch('https://' + RESOURCE + '/' + action, {
            method: 'POST',
            body: '{}'
        }).catch(function () {});
    }

    // Cache-bust the iframe URL so CEF never serves a stale index.html.
    function bust(url) {
        if (!url) return url;
        return url + (url.indexOf('?') === -1 ? '?' : '&') + '_cb=' + Date.now();
    }

    function openTablet(url, dimmer) {
        // Reload only on first open or URL change; tabletURL holds the base URL.
        if (tabletURL !== url) {
            tabletURL = url;
            tabletFrame.src = bust(url);
        }
        dimmerEnabled = !!dimmer;
        tablet.classList.remove('hidden');
        tablet.classList.remove('dimmed');
    }

    function closeTablet() {
        nuiPost('closeTablet');
        tablet.classList.add('hidden');
    }

    $('#closeTablet').addEventListener('click', closeTablet);

    // ESC key closes tablet (capture phase - works when main document has focus)
    window.addEventListener('keydown', function (e) {
        if (e.key === 'Escape' && !tablet.classList.contains('hidden')) {
            e.preventDefault();
            e.stopPropagation();
            closeTablet();
        }
    }, true);

    // ─── Optional dimmer (Config.TabletDimmer) ─────────────────────────────
    tablet.addEventListener('mouseenter', function () {
        if (dimmerEnabled) tablet.classList.remove('dimmed');
    });
    tablet.addEventListener('mouseleave', function () {
        if (dimmerEnabled && !tablet.classList.contains('hidden')) {
            tablet.classList.add('dimmed');
        }
    });

    // ─── Call Popup ──────────────────────────────────────────────────────────

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

    // ─── NUI Message Handler ─────────────────────────────────────────────────

    window.addEventListener('message', function (event) {
        var data = event.data;
        if (!data || !data.type) return;

        switch (data.type) {
            case 'openTablet':
                openTablet(data.url, data.dimmer);
                break;

            case 'closeTablet':
                tablet.classList.add('hidden');
                break;

            case 'reloadTablet':
                if (tabletURL) {
                    tabletFrame.src = bust(tabletURL);
                }
                break;

            case 'showPopup':
                callPopup.classList.remove('hidden');
                break;

            case 'hidePopup':
                callPopup.classList.add('hidden');
                break;

            case 'updateCalls':
                var calls = data.calls || [];
                var idx   = (data.callIndex || 1) - 1; // Lua is 1-indexed
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
