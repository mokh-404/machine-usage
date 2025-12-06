// System Monitor App Logic

const API_ENDPOINT = '/data/metrics.json';
const REFRESH_RATE = 2000; // 2 seconds

// DOM Elements
const els = {
    updated: document.getElementById('last-updated'),

    cpu: {
        percent: document.getElementById('cpu-percent'),
        bar: document.getElementById('cpu-bar'),
        temp: document.getElementById('cpu-temp'),
        model: document.getElementById('cpu-model')
    },

    ram: {
        percent: document.getElementById('ram-percent'),
        bar: document.getElementById('ram-bar'),
        used: document.getElementById('ram-used'),
        total: document.getElementById('ram-total')
    },

    gpu: {
        percent: document.getElementById('gpu-percent'),
        bar: document.getElementById('gpu-bar'),
        model: document.getElementById('gpu-model'),
        temp: document.getElementById('gpu-temp'),
        mem: document.getElementById('gpu-mem'),
        fan: document.getElementById('gpu-fan')
    },

    net: {
        speed: document.getElementById('net-speed'),
        lan: document.getElementById('lan-speed'),
        wifi: document.getElementById('wifi-speed'),
        wifiName: document.getElementById('wifi-name')
    },

    disk: {
        list: document.getElementById('disk-list'),
        smart: document.getElementById('disk-smart')
    },

    alerts: document.getElementById('alerts-container')
};

async function fetchData() {
    try {
        // Add timestamp to prevent caching
        const response = await fetch(`${API_ENDPOINT}?t=${Date.now()}`);
        if (!response.ok) throw new Error('Network response was not ok');
        const data = await response.json();
        updateUI(data);
    } catch (error) {
        console.error('Fetch error:', error);
        els.updated.textContent = 'Connection Lost - Retrying...';
        els.updated.style.color = '#ff2a6d';
    }
}

function updateUI(data) {
    // Timestamp
    els.updated.textContent = `Last Updated: ${data.timestamp}`;
    els.updated.style.color = 'var(--text-dim)';

    // CPU
    updateMetric(els.cpu, data.cpu);

    // RAM
    updateMetric(els.ram, data.ram);
    els.ram.used.textContent = data.ram.used_gb;
    els.ram.total.textContent = data.ram.total_gb;

    // GPU
    els.gpu.percent.textContent = formatInt(data.gpu.usage_percent);
    els.gpu.bar.style.width = `${formatInt(data.gpu.usage_percent)}%`;
    els.gpu.model.textContent = `${data.gpu.vendor} ${data.gpu.model}`;
    els.gpu.temp.textContent = data.gpu.temperature_c ? `${data.gpu.temperature_c}°C` : '--°C';
    els.gpu.mem.textContent = `${data.gpu.memory_used_gb || '--'} / ${data.gpu.memory_total_gb || '--'} GB`;
    els.gpu.fan.textContent = data.gpu.fan_speed_percent ? `${data.gpu.fan_speed_percent}%` : '--%';

    // Network
    els.net.speed.textContent = data.network.total_kb_sec;
    els.net.lan.textContent = data.network.lan_speed || 'Not Connected';
    els.net.wifi.textContent = data.network.wifi_speed || 'Not Connected';
    els.net.wifiName.textContent = data.network.wifi_model ? `${data.network.wifi_model} (${data.network.wifi_type})` : '';

    // Disks
    renderDisks(data.disk);

    // Alerts
    renderAlerts(data.alerts);
}

function updateMetric(elGroup, dataObj) {
    if (elGroup.percent) {
        elGroup.percent.textContent = formatInt(dataObj.percent);
    }
    if (elGroup.bar) {
        elGroup.bar.style.width = `${formatInt(dataObj.percent)}%`;
    }
    if (elGroup.temp) {
        elGroup.temp.textContent = dataObj.temperature_c ? `${dataObj.temperature_c}°C` : '--°C';
    }
    if (elGroup.model && dataObj.cpu_model_name) {
        elGroup.model.textContent = dataObj.cpu_model_name;
    }
}

function renderDisks(diskData) {
    els.disk.smart.textContent = `SMART: ${diskData.smart_status}`;
    els.disk.smart.className = diskData.smart_status.includes('Healthy') ? 'status-badge success' : 'status-badge warning';

    // Handle drives array
    let drives = [];
    if (Array.isArray(diskData.drives)) {
        drives = diskData.drives;
    } else {
        // Fallback for older JSON format or parsing issues
        drives = [];
    }

    els.disk.list.innerHTML = drives.map(drive => `
        <div class="disk-item">
            <div class="disk-header">
                <div class="disk-name">${drive.Name} <span class="disk-type">${drive.Type || ''}</span></div>
                <div class="disk-info">
                    ${drive.Used} GB / ${drive.Total} GB
                    <span>(${drive.Percent}%)</span>
                </div>
            </div>
            <div class="progress-bar">
                <div class="fill" style="width: ${drive.Percent}%; background-color: ${getDiskColor(drive.Percent)}"></div>
            </div>
        </div>
    `).join('');
}

function renderAlerts(alerts) {
    if (!alerts) {
        els.alerts.innerHTML = '';
        return;
    }

    let alertList = [];
    if (Array.isArray(alerts)) {
        alertList = alerts;
    } else if (typeof alerts === 'string') {
        alertList = [alerts];
    }

    if (alertList.length === 0) {
        els.alerts.innerHTML = '';
        return;
    }

    els.alerts.innerHTML = alertList.map(msg => `
        <div class="alert-box">
            <strong>⚠ ALERT:</strong> ${msg}
        </div>
    `).join('');
}

function formatInt(val) {
    return Math.round(Number(val) || 0);
}

function getDiskColor(percent) {
    if (percent > 90) return '#ff2a6d'; // Danger
    if (percent > 75) return '#ff9f1c'; // Warning
    return '#00f3ff'; // Normal
}

// Start
fetchData();
setInterval(fetchData, REFRESH_RATE);
