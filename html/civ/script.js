
let hideTimeout = null;

window.addEventListener('message', function(event) {
    const data = event.data;
    
    if (data.action === 'showID') {
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
    
    container.style.animation = 'none';
    container.offsetHeight;
    
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
        renderMugshot(photoContainer, mugshotUrl);
    } else if (ssn) {
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
        var parent = this.parentElement;
        if (parent) parent.innerHTML = '<span class="no-photo">NO PHOTO</span>';
    };
    img.src = src;
    container.appendChild(img);
}

function normaliseMugshotSrc(value) {
    if (!value) return '';
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

document.addEventListener('click', function(e) {
    if (e.target.closest('#id-card-container')) {
        hideIDCard();
    }
});

document.addEventListener('keydown', function(e) {
    if (e.key === 'Escape') {
        hideIDCard();
        fetch(`https://${GetParentResourceName()}/escape`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({})
        });
    }
});
