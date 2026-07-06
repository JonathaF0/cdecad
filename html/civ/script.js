// CDECAD Civilian Manager - ID Card NUI Script

let hideTimeout = null;

window.addEventListener('message', function(event) {
    const data = event.data;
    
    if (data.action === 'showID') {
        // licenseMode = 'template' | 'auto' | 'html'
        const mode = data.licenseMode || 'html';
        if ((mode === 'template' || mode === 'auto') && data.civilianId) {
            showTemplateCard(data.civilianId, data.licenseType || 'drivers',
                             data.civilian, data.from, data.duration, data.style, mode);
        } else {
            showIDCard(data.civilian, data.from, data.duration, data.style);
        }
    } else if (data.action === 'hideID') {
        hideIDCard();
    }
});

function showIDCard(civilian, from, duration, style) {
    if (hideTimeout) {
        clearTimeout(hideTimeout);
        hideTimeout = null;
    }
    
    const container = document.getElementById('id-card-container');
    const card = document.getElementById('id-card');
    
    // Reset animation
    container.style.animation = 'none';
    container.offsetHeight; // Trigger reflow
    
    if (style) {
        if (style.BackgroundColor) {
            card.style.background = `linear-gradient(135deg, ${style.BackgroundColor} 0%, ${lightenColor(style.BackgroundColor, 20)} 50%, ${style.BackgroundColor} 100%)`;
        }
        if (style.StateName) {
            document.querySelector('.state-name').textContent = style.StateName.toUpperCase();
        }
        if (style.CardTitle) {
            document.querySelector('.card-title').textContent = style.CardTitle;
        }
    } else {
        document.querySelector('.state-name').textContent = 'SAN ANDREAS';
        document.querySelector('.card-title').textContent = 'DRIVER LICENSE';
    }
    
    // Clear fields to avoid stale data
    document.getElementById('civ-ssn').textContent = '-';
    document.getElementById('civ-name').textContent = '-';
    document.getElementById('civ-dob').textContent = '-';
    document.getElementById('civ-sex').textContent = '-';
    document.getElementById('civ-eyes').textContent = '-';
    document.getElementById('civ-height').textContent = '-';
    document.getElementById('civ-weight').textContent = '-';
    document.getElementById('civ-address').textContent = '-';
    document.getElementById('shown-by').textContent = '';
    document.getElementById('civilian-signature').textContent = '';
    
    document.getElementById('civ-ssn').textContent = civilian.ssn || civilian.citizenid || 'N/A';
    document.getElementById('civ-name').textContent = `${civilian.lastName || ''}, ${civilian.firstName || ''}`.toUpperCase();
    document.getElementById('civ-dob').textContent = formatDate(civilian.dob || civilian.dateOfBirth);
    document.getElementById('civ-sex').textContent = formatGender(civilian.gender);
    document.getElementById('civ-eyes').textContent = (civilian.eyeColor || 'BRN').toUpperCase().substring(0, 3);
    document.getElementById('civ-height').textContent = civilian.height || "5'10\"";
    document.getElementById('civ-weight').textContent = civilian.weight ? `${civilian.weight} lbs` : '180 lbs';
    document.getElementById('civ-address').textContent = civilian.address || 'Los Santos, SA';
    document.getElementById('shown-by').textContent = `Shown by: ${from}`;
    
    document.getElementById('civilian-signature').textContent = `${civilian.firstName || ''} ${civilian.lastName || ''}`;
    
    var photoContainer = document.getElementById('civilian-photo');
    if (!photoContainer) return;

    var mugshotUrl = civilian.mugshotUrl;
    var ssn = civilian.ssn || civilian.citizenid;

    if (mugshotUrl && mugshotUrl.startsWith('data:')) {
        // Self-contained data URI - display directly, no network needed
        renderMugshot(photoContainer, mugshotUrl);
    } else if (ssn) {
        // Fetch via the resource server, which holds the CAD API key
        photoContainer.innerHTML = '<span class="no-photo" style="font-size:9px;color:#6b7280">LOADING...</span>';
        fetch('https://' + GetParentResourceName() + '/getMugshot', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ ssn: ssn })
        })
        .then(function(r) { return r.ok ? r.json() : null; })
        .then(function(data) {
            var el = document.getElementById('civilian-photo');
            if (!el) return;
            if (data && data.mugshotUrl) {
                renderMugshot(el, data.mugshotUrl);
            } else {
                el.innerHTML = '<span class="no-photo">NO PHOTO</span>';
            }
        })
        .catch(function() {
            var el = document.getElementById('civilian-photo');
            if (el) el.innerHTML = '<span class="no-photo">NO PHOTO</span>';
        });
    } else if (mugshotUrl) {
        // HTTP URL with no API config - try direct (may fail due to CORS/expiry)
        renderMugshot(photoContainer, mugshotUrl);
    } else {
        photoContainer.innerHTML = '<span class="no-photo">NO PHOTO</span>';
    }
    
    container.classList.remove('hidden');
    container.style.animation = 'fadeIn 0.3s ease-out';
    
    hideTimeout = setTimeout(function() {
        hideIDCard();
    }, duration || 10000);
    
    console.log('[CDECAD-CIVMANAGER] Showing ID for:', civilian.firstName, civilian.lastName);
}

// Templated ID card: a PNG rendered server-side from the community's license
// template, fetched through the /fetchLicensePng proxy.
// mode='auto' falls back to the HTML card on miss.
function showTemplateCard(civilianId, licenseType, civilian, from, duration, style, mode) {
    if (hideTimeout) {
        clearTimeout(hideTimeout);
        hideTimeout = null;
    }
    const container = document.getElementById('id-card-container');
    if (!container) return;

    const card = document.getElementById('id-card');
    if (card) card.style.display = 'none';

    let imgWrap = document.getElementById('id-card-template-wrap');
    if (!imgWrap) {
        imgWrap = document.createElement('div');
        imgWrap.id = 'id-card-template-wrap';
        imgWrap.style.cssText = 'display:flex;flex-direction:column;align-items:center;gap:8px;';
        container.appendChild(imgWrap);
    }
    imgWrap.style.display = '';
    imgWrap.innerHTML = '<div style="color:#cbd5e1;font-family:sans-serif;font-size:13px;">Loading license…</div>';

    function fallback() {
        imgWrap.style.display = 'none';
        if (card) card.style.display = '';
        showIDCard(civilian, from, duration, style);
    }

    function failHard(msg) {
        imgWrap.innerHTML = '<div style="color:#fff;background:#1f2937;padding:14px 18px;border-radius:8px;font-family:sans-serif;font-size:13px;">' + (msg || 'License template unavailable.') + '</div>';
        container.classList.remove('hidden');
        container.style.animation = 'fadeIn 0.3s ease-out';
        hideTimeout = setTimeout(function() { hideIDCard(); }, duration || 10000);
    }

    fetch('https://' + GetParentResourceName() + '/fetchLicensePng', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ civilianId: civilianId, licenseType: licenseType }),
    })
    .then(function(r) { return r.ok ? r.json() : null; })
    .then(function(payload) {
        if (!payload || !payload.ok || !payload.dataUri) {
            return mode === 'auto' ? fallback() : failHard();
        }
        imgWrap.innerHTML = '';
        const img = document.createElement('img');
        img.alt = 'License';
        img.style.cssText = 'max-width:520px;width:100%;border-radius:10px;box-shadow:0 8px 32px rgba(0,0,0,0.4);';
        img.onerror = function() { return mode === 'auto' ? fallback() : failHard(); };
        img.src = payload.dataUri;
        imgWrap.appendChild(img);

        const credit = document.createElement('div');
        credit.style.cssText = 'color:#cbd5e1;font-family:sans-serif;font-size:12px;text-shadow:0 1px 2px rgba(0,0,0,0.6);';
        credit.textContent = 'Shown by: ' + (from || '');
        imgWrap.appendChild(credit);

        container.classList.remove('hidden');
        container.style.animation = 'fadeIn 0.3s ease-out';
        hideTimeout = setTimeout(function() { hideIDCard(); }, duration || 10000);
    })
    .catch(function() {
        return mode === 'auto' ? fallback() : failHard();
    });
}

function hideIDCard() {
    const container = document.getElementById('id-card-container');
    container.style.animation = 'fadeOut 0.3s ease-out';
    
    setTimeout(function() {
        container.classList.add('hidden');
    }, 300);
    
    // Notify client
    fetch(`https://${GetParentResourceName()}/closeID`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({})
    });
}

function renderMugshot(container, value) {
    const src = normaliseMugshotSrc(value);
    container.innerHTML = '';
    const img = document.createElement('img');
    img.alt = 'Photo';
    img.onerror = function() {
        // img may be detached if showIDCard was called twice rapidly
        var parent = this.parentElement;
        if (parent) parent.innerHTML = '<span class="no-photo">NO PHOTO</span>';
    };
    img.src = src;
    container.appendChild(img);
}

// Normalise a mugshot value to a usable <img src> string.
// MugShotBase64 returns raw base64 with no prefix; detect JPEG ("/9j")
// vs PNG from the header bytes since the wrong MIME type fires onerror.
function normaliseMugshotSrc(value) {
    if (!value) return '';
    // Data URI or remote URL - use as-is
    if (value.startsWith('data:') || value.startsWith('http://') || value.startsWith('https://')) {
        return value;
    }
    const mime = value.startsWith('/9j') ? 'image/jpeg' : 'image/png';
    return `data:${mime};base64,` + value;
}

function formatDate(dateStr) {
    if (!dateStr) return 'N/A';
    
    try {
        const date = new Date(dateStr);
        const month = String(date.getMonth() + 1).padStart(2, '0');
        const day = String(date.getDate()).padStart(2, '0');
        const year = date.getFullYear();
        return `${month}/${day}/${year}`;
    } catch (e) {
        return dateStr;
    }
}

function formatGender(gender) {
    if (!gender) return 'U';
    
    const g = gender.toString().toLowerCase();
    if (g === 'male' || g === 'm' || g === '0') return 'M';
    if (g === 'female' || g === 'f' || g === '1') return 'F';
    return 'X';
}

function lightenColor(color, percent) {
    if (!color) return '#2c5282';
    
    color = color.replace('#', '');
    
    let r = parseInt(color.substring(0, 2), 16);
    let g = parseInt(color.substring(2, 4), 16);
    let b = parseInt(color.substring(4, 6), 16);
    
    r = Math.min(255, Math.floor(r + (255 - r) * (percent / 100)));
    g = Math.min(255, Math.floor(g + (255 - g) * (percent / 100)));
    b = Math.min(255, Math.floor(b + (255 - b) * (percent / 100)));
    
    return '#' + ((1 << 24) + (r << 16) + (g << 8) + b).toString(16).slice(1);
}

// Close on click
document.addEventListener('click', function(e) {
    if (e.target.closest('#id-card-container')) {
        hideIDCard();
    }
});

// Close on escape key
document.addEventListener('keydown', function(e) {
    if (e.key === 'Escape') {
        if (!document.getElementById('bank-panel').classList.contains('hidden')) {
            closeBank();
            return;
        }
        hideIDCard();
        fetch(`https://${GetParentResourceName()}/escape`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({})
        });
    }
});

// Bank panel

let bankCivilianId  = null;
let bankCommunityId = null;
let bankPlayerCash  = null; // available in-game cash; null = unknown

window.addEventListener('message', function(event) {
    const data = event.data;
    if (data.action === 'openBank') {
        openBank(data.account, data.civilian, data.communityId, data.playerCash);
    } else if (data.action === 'openAdminBank') {
        openAdminBank(data.accounts || [], data.settings || {}, data.communityId);
    }
});

// Bank-employee view: lists every community account with search + summary.
// Heavier admin actions live in the CAD "Banking" admin page.
function openAdminBank(accounts, settings, communityId) {
    let panel = document.getElementById('admin-bank-panel');
    if (!panel) {
        panel = document.createElement('div');
        panel.id = 'admin-bank-panel';
        panel.className = 'modal admin-bank-modal';
        panel.innerHTML =
            '<div class="modal-card admin-bank-card">' +
            '  <div class="modal-header">' +
            '    <h2>Admin Bank</h2>' +
            '    <button id="admin-bank-close" class="btn btn-ghost">Close</button>' +
            '  </div>' +
            '  <div class="admin-bank-summary" id="admin-bank-summary"></div>' +
            '  <input id="admin-bank-search" placeholder="Search by name, SSN, or account #" class="admin-bank-input" />' +
            '  <div class="admin-bank-accounts" id="admin-bank-accounts"></div>' +
            '  <div class="admin-bank-footer">' +
            '    <small>For loan approvals & full settings, open the Banking section of the CAD admin panel.</small>' +
            '  </div>' +
            '</div>';
        document.body.appendChild(panel);
        panel.querySelector('#admin-bank-close').addEventListener('click', function() {
            panel.classList.add('hidden');
            nuiFetch('closeBank', {});
        });
        panel.querySelector('#admin-bank-search').addEventListener('input', function(e) {
            renderAdminAccounts(accounts, e.target.value);
        });
    }
    panel.classList.remove('hidden');

    const totalDeposits = accounts.reduce(function(s, a) { return s + (a.balance || 0); }, 0);
    const pendingLoans  = accounts.reduce(function(s, a) { return s + (a.pendingLoans || 0); }, 0);
    const summary = document.getElementById('admin-bank-summary');
    summary.innerHTML =
        '<div class="ab-stat"><div class="ab-label">Accounts</div><div class="ab-value">' + accounts.length + '</div></div>' +
        '<div class="ab-stat"><div class="ab-label">Total Deposits</div><div class="ab-value">$' + totalDeposits.toLocaleString() + '</div></div>' +
        '<div class="ab-stat"><div class="ab-label">Pending Loans</div><div class="ab-value">' + pendingLoans + '</div></div>';

    renderAdminAccounts(accounts, '');
}

// Selected account in the admin panel - rebuilt every time the list re-renders
let adminSelectedAccountId = null;

function renderAdminAccounts(accounts, query) {
    const list = document.getElementById('admin-bank-accounts');
    const q = (query || '').toLowerCase().trim();
    const filtered = !q ? accounts : accounts.filter(function(a) {
        const civ = a.civilian || {};
        const haystack = [
            civ.firstName, civ.lastName, civ.ssn, a.accountNumber
        ].filter(Boolean).join(' ').toLowerCase();
        return haystack.indexOf(q) !== -1;
    });

    if (!filtered.length) {
        list.innerHTML = '<div class="tx-empty">No matching accounts</div>';
        return;
    }

    list.innerHTML = filtered.map(function(a) {
        const civ = a.civilian || {};
        return '<div class="ab-row" data-account-id="' + esc(a._id) + '" role="button" tabindex="0">' +
            '  <div class="ab-row-name">' + esc((civ.firstName || '') + ' ' + (civ.lastName || '')) + '</div>' +
            '  <div class="ab-row-meta">' + esc(a.accountNumber || '-') + (civ.ssn ? ' &middot; SSN ' + esc(civ.ssn) : '') + '</div>' +
            '  <div class="ab-row-balance">$' + Number(a.balance || 0).toLocaleString() + '</div>' +
            (a.pendingLoans ? '<div class="ab-row-pill">Pending loans: ' + a.pendingLoans + '</div>' : '') +
            '</div>';
    }).join('');

    // Row click opens the per-account banker view
    list.querySelectorAll('.ab-row').forEach(function(row) {
        row.addEventListener('click', function() {
            adminSelectedAccountId = row.getAttribute('data-account-id');
            openBankerAccount(adminSelectedAccountId);
        });
    });
}

// Per-account banker view; loads details via the /banking/fivem/admin-account proxy.
function openBankerAccount(accountId) {
    let panel = document.getElementById('banker-account-panel');
    if (!panel) {
        panel = document.createElement('div');
        panel.id = 'banker-account-panel';
        panel.className = 'modal admin-bank-modal';
        panel.innerHTML =
            '<div class="modal-card admin-bank-card">' +
            '  <div class="modal-header">' +
            '    <h2 id="banker-acct-title">Account</h2>' +
            '    <button id="banker-acct-close" class="btn btn-ghost">Close</button>' +
            '  </div>' +
            '  <div id="banker-acct-body" class="banker-acct-body"><em>Loading…</em></div>' +
            '</div>';
        document.body.appendChild(panel);
        panel.querySelector('#banker-acct-close').addEventListener('click', function() {
            panel.classList.add('hidden');
        });
    }
    panel.classList.remove('hidden');

    nuiFetch('bankerLoadAccount', { accountId: accountId }).then(function(res) {
        if (!res || !res.success) {
            document.getElementById('banker-acct-body').textContent = (res && res.error) || 'Failed to load account';
            return;
        }
        renderBankerAccount(res.account);
    });
}

function renderBankerAccount(a) {
    const civ = a.civilian || {};
    const title = (civ.firstName || '') + ' ' + (civ.lastName || '') + ' - ' + (a.accountNumber || '');
    document.getElementById('banker-acct-title').textContent = title.trim() || 'Account';

    const pending = (a.loans || []).filter(function(l) { return l.status === 'pending'; });
    const active  = (a.loans || []).filter(function(l) { return l.status === 'active'; });

    const pendingHtml = pending.length === 0 ? '' :
        '<h3>Pending Loan Approvals</h3>' +
        '<div class="banker-list">' + pending.map(function(l) {
            return '<div class="banker-row">' +
                '<div><strong>' + esc(l.productName) + '</strong> - $' + Number(l.principal).toLocaleString() +
                ' @ ' + (l.apr * 100).toFixed(2) + '% / ' + l.termMonths + 'mo</div>' +
                '<div class="banker-row-actions">' +
                '  <button class="btn btn-primary btn-green" data-action="approve" data-loan-id="' + esc(l._id) + '">Approve</button>' +
                '  <button class="btn btn-primary btn-red"   data-action="deny"    data-loan-id="' + esc(l._id) + '">Deny</button>' +
                '</div></div>';
        }).join('') + '</div>';

    const activeHtml =
        '<h3>Active Loans (' + active.length + ')</h3>' +
        (active.length === 0 ? '<div class="tx-empty">None</div>' :
            '<div class="banker-list">' + active.map(function(l) {
                return '<div class="banker-row"><div>' + esc(l.productName) +
                    ' - bal $' + Number(l.balance).toLocaleString() +
                    ' &middot; next due ' + (l.nextPaymentDue ? new Date(l.nextPaymentDue).toLocaleDateString() : '-') +
                    '</div></div>';
            }).join('') + '</div>');

    const statusHtml =
        '<h3>Account Status: ' + esc(a.accountStatus || 'active') + '</h3>' +
        '<div class="banker-row-actions">' +
        '  <button class="btn btn-primary" data-action="status" data-status="active">Active</button>' +
        '  <button class="btn btn-primary btn-red" data-action="status" data-status="frozen">Freeze</button>' +
        '  <button class="btn btn-primary btn-red" data-action="status" data-status="closed">Close</button>' +
        '</div>';

    const actHtml =
        '<h3>Act on Behalf (Teller)</h3>' +
        '<div class="banker-act"><input id="banker-amount" type="number" placeholder="Amount" min="0" step="0.01" />' +
        '  <input id="banker-desc" placeholder="Note" />' +
        '  <input id="banker-recipient" placeholder="Recipient acct # (transfer only)" />' +
        '  <div class="banker-row-actions">' +
        '    <button class="btn btn-primary btn-green" data-action="adjust" data-mode="deposit">Deposit</button>' +
        '    <button class="btn btn-primary"           data-action="adjust" data-mode="withdraw">Withdraw</button>' +
        '    <button class="btn btn-primary"           data-action="adjust" data-mode="transfer">Transfer</button>' +
        '  </div></div>';

    document.getElementById('banker-acct-body').innerHTML =
        '<div class="banker-summary">Balance: <strong>$' + Number(a.balance || 0).toLocaleString() + '</strong></div>' +
        pendingHtml + activeHtml + statusHtml + actHtml;

    // Wire up button clicks
    const body = document.getElementById('banker-acct-body');
    body.querySelectorAll('button[data-action]').forEach(function(btn) {
        btn.addEventListener('click', function() {
            const action = btn.getAttribute('data-action');
            if (action === 'approve' || action === 'deny') {
                bankerLoanDecide(a._id, btn.getAttribute('data-loan-id'), action);
            } else if (action === 'status') {
                bankerSetStatus(a._id, btn.getAttribute('data-status'));
            } else if (action === 'adjust') {
                const amount = parseFloat(document.getElementById('banker-amount').value);
                const description = document.getElementById('banker-desc').value;
                const recipientAccountNumber = document.getElementById('banker-recipient').value;
                bankerAdjust(a._id, btn.getAttribute('data-mode'), amount, description, recipientAccountNumber);
            }
        });
    });
}

function bankerLoanDecide(accountId, loanId, decision) {
    const reason = decision === 'deny' ? (window.prompt('Denial reason (optional):') || '') : '';
    nuiFetch('bankerLoanDecision', { accountId: accountId, loanId: loanId, decision: decision, reason: reason }).then(function(res) {
        if (res && res.success) openBankerAccount(accountId);
        else alert((res && res.error) || 'Failed');
    });
}
function bankerSetStatus(accountId, status) {
    nuiFetch('bankerSetStatus', { accountId: accountId, status: status }).then(function(res) {
        if (res && res.success) openBankerAccount(accountId);
        else alert((res && res.error) || 'Failed');
    });
}
function bankerAdjust(accountId, action, amount, description, recipientAccountNumber) {
    if (!Number.isFinite(amount) || amount <= 0) { alert('Enter a valid amount'); return; }
    nuiFetch('bankerAdjust', {
        accountId: accountId,
        action: action,
        amount: amount,
        description: description,
        recipientAccountNumber: recipientAccountNumber || ''
    }).then(function(res) {
        if (res && res.success) openBankerAccount(accountId);
        else alert((res && res.error) || 'Failed');
    });
}

function nuiFetch(endpoint, payload) {
    return fetch(`https://${GetParentResourceName()}/${endpoint}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload || {})
    }).then(r => r.json()).catch(() => ({ success: false, error: 'Request failed' }));
}

function openBank(account, civilian, communityId, playerCash) {
    bankCivilianId  = civilian.id;
    bankCommunityId = communityId;
    bankPlayerCash  = (typeof playerCash === 'number') ? playerCash : null;

    document.getElementById('bank-civ-name').textContent =
        (civilian.firstName || '') + ' ' + (civilian.lastName || '');
    document.getElementById('bank-account-num').textContent =
        account.accountNumber || 'ACC---------';
    document.getElementById('bank-status-badge').textContent =
        (account.accountStatus || 'active').toUpperCase();

    // Show available cash in deposit tab
    const cashEl = document.getElementById('deposit-cash-available');
    if (cashEl) {
        cashEl.textContent = bankPlayerCash !== null
            ? '$' + bankPlayerCash.toLocaleString('en-US', { minimumFractionDigits: 2 })
            : '-';
    }

    updateBalance(account.balance || 0);
    renderTransactions(account.transactions || []);

    showTab('transactions');
    document.getElementById('bank-panel').classList.remove('hidden');
}

function closeBank() {
    document.getElementById('bank-panel').classList.add('hidden');
    nuiFetch('closeBank', {});
}

function updateBalance(amount) {
    const el = document.getElementById('bank-balance');
    el.textContent = '$' + Number(amount).toLocaleString('en-US', {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2
    });
    el.style.color = amount < 0 ? '#ef4444' : '#10b981';
}

function renderTransactions(txs) {
    const list = document.getElementById('transaction-list');
    if (!txs || txs.length === 0) {
        list.innerHTML = '<div class="tx-empty">No transactions yet</div>';
        return;
    }

    const iconMap = {
        deposit:    { cls: 'deposit',    sym: '↓' },
        withdrawal: { cls: 'withdrawal', sym: '↑' },
        transfer:   { cls: 'transfer',   sym: '⇄' },
        fine:       { cls: 'fine',       sym: '!' },
        ticket:     { cls: 'fine',       sym: '!' },
        salary:     { cls: 'salary',     sym: '★' },
        payment:    { cls: 'transfer',   sym: '⇄' },
    };

    const creditTypes = ['deposit', 'salary'];

    const rows = [...txs].reverse().slice(0, 50).map(tx => {
        const info = iconMap[tx.type] || { cls: 'transfer', sym: '•' };
        const isCredit = creditTypes.includes(tx.type);
        const amtClass = isCredit ? 'plus' : 'minus';
        const amtSign  = isCredit ? '+' : '-';
        const amtStr   = amtSign + '$' + Number(tx.amount).toLocaleString('en-US', { minimumFractionDigits: 2 });
        const dateStr  = tx.date ? new Date(tx.date).toLocaleString('en-US', { month:'short', day:'numeric', hour:'2-digit', minute:'2-digit' }) : '';

        return `<div class="tx-item">
            <div class="tx-icon ${info.cls}">${info.sym}</div>
            <div class="tx-body">
                <div class="tx-desc">${esc(tx.description || tx.type)}</div>
                <div class="tx-date">${esc(dateStr)}</div>
            </div>
            <div class="tx-amount ${amtClass}">${amtStr}</div>
        </div>`;
    });

    list.innerHTML = rows.join('');
}

function esc(str) {
    if (str == null) return '';
    const d = document.createElement('div');
    d.textContent = String(str);
    return d.innerHTML;
}

function showTab(name) {
    document.querySelectorAll('.bank-tab').forEach(t => t.classList.add('hidden'));
    document.querySelectorAll('.bank-nav-btn').forEach(b => b.classList.remove('active'));
    const tab = document.getElementById('tab-' + name);
    if (tab) tab.classList.remove('hidden');
    const btn = document.querySelector(`.bank-nav-btn[data-tab="${name}"]`);
    if (btn) btn.classList.add('active');
}

function showMsg(id, type, text) {
    const el = document.getElementById(id);
    if (!el) return;
    el.className = 'form-msg ' + type;
    el.textContent = text;
    setTimeout(() => { el.className = 'form-msg hidden'; }, 4000);
}

// Nav tab switching
document.querySelectorAll('.bank-nav-btn').forEach(btn => {
    btn.addEventListener('click', () => showTab(btn.dataset.tab));
});

// Close button
document.getElementById('bank-close').addEventListener('click', closeBank);

// Refresh transactions
document.getElementById('btn-refresh').addEventListener('click', async function() {
    if (!bankCivilianId) return;
    this.style.opacity = '0.4';
    const res = await nuiFetch('bankDeposit', { civilianId: bankCivilianId, amount: 0, description: '' });
    // Zero-amount deposit re-opens the panel with fresh data via the callback
    this.style.opacity = '1';
});

// Deposit
document.getElementById('btn-deposit').addEventListener('click', async function() {
    const amount = parseFloat(document.getElementById('deposit-amount').value);
    const desc   = document.getElementById('deposit-desc').value.trim();

    if (!amount || amount <= 0) { showMsg('deposit-msg', 'error', 'Enter a valid amount'); return; }
    if (!desc)                  { showMsg('deposit-msg', 'error', 'Enter a description');  return; }

    // Client-side cash guard - server also validates this independently
    if (bankPlayerCash !== null && amount > bankPlayerCash) {
        showMsg('deposit-msg', 'error',
            'Insufficient cash. You have $' +
            bankPlayerCash.toLocaleString('en-US', { minimumFractionDigits: 2 }) + ' available.');
        return;
    }

    this.disabled = true;
    const res = await nuiFetch('bankDeposit', { civilianId: bankCivilianId, amount, description: desc });
    this.disabled = false;

    if (res && res.success) {
        updateBalance(res.balance);
        showMsg('deposit-msg', 'success', 'Deposit successful! New balance: $' + Number(res.balance).toLocaleString('en-US', { minimumFractionDigits: 2 }));
        document.getElementById('deposit-amount').value = '';
        document.getElementById('deposit-desc').value = '';
        // Subtract from locally tracked cash
        if (bankPlayerCash !== null) {
            bankPlayerCash = Math.max(0, bankPlayerCash - amount);
            const cashEl = document.getElementById('deposit-cash-available');
            if (cashEl) cashEl.textContent = '$' + bankPlayerCash.toLocaleString('en-US', { minimumFractionDigits: 2 });
        }
        if (res.transaction) {
            const list = document.getElementById('transaction-list');
            if (list.querySelector('.tx-empty')) list.innerHTML = '';
            list.insertAdjacentHTML('afterbegin', buildTxRow(res.transaction));
        }
    } else {
        showMsg('deposit-msg', 'error', (res && res.error) || 'Deposit failed');
    }
});

// Withdraw
document.getElementById('btn-withdraw').addEventListener('click', async function() {
    const amount = parseFloat(document.getElementById('withdraw-amount').value);
    const desc   = document.getElementById('withdraw-desc').value.trim();

    if (!amount || amount <= 0) { showMsg('withdraw-msg', 'error', 'Enter a valid amount'); return; }
    if (!desc)                  { showMsg('withdraw-msg', 'error', 'Enter a description');  return; }

    this.disabled = true;
    const res = await nuiFetch('bankWithdraw', { civilianId: bankCivilianId, amount, description: desc });
    this.disabled = false;

    if (res && res.success) {
        updateBalance(res.balance);
        showMsg('withdraw-msg', 'success', 'Withdrawal successful! New balance: $' + Number(res.balance).toLocaleString('en-US', { minimumFractionDigits: 2 }));
        document.getElementById('withdraw-amount').value = '';
        document.getElementById('withdraw-desc').value = '';
        if (res.transaction) {
            const list = document.getElementById('transaction-list');
            if (list.querySelector('.tx-empty')) list.innerHTML = '';
            list.insertAdjacentHTML('afterbegin', buildTxRow(res.transaction));
        }
    } else {
        showMsg('withdraw-msg', 'error', (res && res.error) || 'Withdrawal failed');
    }
});

// Transfer
document.getElementById('btn-transfer').addEventListener('click', async function() {
    const toAcct  = document.getElementById('transfer-to').value.trim();
    const amount  = parseFloat(document.getElementById('transfer-amount').value);
    const desc    = document.getElementById('transfer-desc').value.trim();

    if (!toAcct)                { showMsg('transfer-msg', 'error', 'Enter recipient account number'); return; }
    if (!amount || amount <= 0) { showMsg('transfer-msg', 'error', 'Enter a valid amount');            return; }
    if (!desc)                  { showMsg('transfer-msg', 'error', 'Enter a description');             return; }

    this.disabled = true;
    const res = await nuiFetch('bankTransfer', {
        fromCivilianId: bankCivilianId,
        toAccountNumber: toAcct,
        amount,
        description: desc
    });
    this.disabled = false;

    if (res && res.success) {
        updateBalance(res.balance);
        showMsg('transfer-msg', 'success', 'Transfer sent! New balance: $' + Number(res.balance).toLocaleString('en-US', { minimumFractionDigits: 2 }));
        document.getElementById('transfer-to').value = '';
        document.getElementById('transfer-amount').value = '';
        document.getElementById('transfer-desc').value = '';
        if (res.transaction) {
            const list = document.getElementById('transaction-list');
            if (list.querySelector('.tx-empty')) list.innerHTML = '';
            list.insertAdjacentHTML('afterbegin', buildTxRow(res.transaction));
        }
    } else {
        showMsg('transfer-msg', 'error', (res && res.error) || 'Transfer failed');
    }
});

function buildTxRow(tx) {
    const creditTypes = ['deposit', 'salary'];
    const iconMap = {
        deposit:    { cls: 'deposit',    sym: '↓' },
        withdrawal: { cls: 'withdrawal', sym: '↑' },
        transfer:   { cls: 'transfer',   sym: '⇄' },
        fine:       { cls: 'fine',       sym: '!' },
        ticket:     { cls: 'fine',       sym: '!' },
        salary:     { cls: 'salary',     sym: '★' },
        payment:    { cls: 'transfer',   sym: '⇄' },
    };
    const info = iconMap[tx.type] || { cls: 'transfer', sym: '•' };
    const isCredit = creditTypes.includes(tx.type);
    const amtClass = isCredit ? 'plus' : 'minus';
    const amtSign  = isCredit ? '+' : '-';
    const amtStr   = amtSign + '$' + Number(tx.amount).toLocaleString('en-US', { minimumFractionDigits: 2 });
    const dateStr  = tx.date ? new Date(tx.date).toLocaleString('en-US', { month:'short', day:'numeric', hour:'2-digit', minute:'2-digit' }) : '';
    return `<div class="tx-item">
        <div class="tx-icon ${info.cls}">${info.sym}</div>
        <div class="tx-body">
            <div class="tx-desc">${esc(tx.description || tx.type)}</div>
            <div class="tx-date">${esc(dateStr)}</div>
        </div>
        <div class="tx-amount ${amtClass}">${amtStr}</div>
    </div>`;
}
