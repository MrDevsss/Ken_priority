const app = document.getElementById('app');

function GetParentResourceName() {
    return window.GetParentResourceName ? window.GetParentResourceName() : 'priority_cooldown';
}

function closeUI() {
    fetch(`https://${GetParentResourceName()}/close`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({})
    });
    app.classList.add('hidden');
}

function applyGroupState(group, state) {
    const dot    = document.getElementById(`dot-${group}`);
    const stText = document.getElementById(`status-${group}`);
    const cdVal  = document.getElementById(`cd-${group}`);
    const info   = document.getElementById(`info-${group}`);

    if (!dot || !stText || !cdVal || !info) return;

    const s = state.status || 'safe';

    dot.className    = 'dot ' + s;
    stText.className = 'status-text ' + s;

    const labels = {
        safe:     'SAFE',
        hold:     'ON HOLD',
        progress: 'IN PROGRESS'
    };
    stText.textContent = labels[s] || s.toUpperCase();
    cdVal.textContent  = state.cooldown > 0 ? state.cooldown + 's' : '0';

    if (state.startedBy) {
        info.textContent = `${(state.startedJob || '??').toUpperCase()}: ${state.startedBy}`;
    } else {
        info.textContent = '—';
    }
}

window.addEventListener('message', function(event) {
    const data = event.data;

    if (data.action === 'toggleUI') {
        if (data.show) {
            app.classList.remove('hidden');
        } else {
            app.classList.add('hidden');
        }
    }

    if (data.action === 'updateState') {
        const states = data.states;
        if (states.police)  applyGroupState('police',  states.police);
        if (states.sheriff) applyGroupState('sheriff', states.sheriff);
    }
});

// Default
applyGroupState('police',  { status: 'safe', cooldown: 0, startedBy: null, startedJob: null });
applyGroupState('sheriff', { status: 'safe', cooldown: 0, startedBy: null, startedJob: null });