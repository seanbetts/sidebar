const status = document.getElementById("status");

const setStatus = (text) => {
    status.textContent = text;
};

const getActiveTab = async () => {
    const tabs = await browser.tabs.query({ active: true, currentWindow: true });
    return tabs && tabs[0] ? tabs[0] : null;
};

const saveUrl = async (url) => {
    const response = await browser.runtime.sendNativeMessage({
        action: "save_url",
        url
    });
    if (response && response.ok) {
        setStatus("✓ Saved for later.");
        return true;
    }
    setStatus(response?.error ?? "Save failed.");
    return false;
};

const saveCurrentTab = async () => {
    setStatus("Saving...");
    try {
        const tab = await getActiveTab();
        const url = tab?.url ?? null;
        if (!url) {
            setStatus("No active tab URL.");
            return false;
        }
        return await saveUrl(url);
    } catch (error) {
        setStatus(error?.message ?? "Save failed.");
        return false;
    }
};

const saveWithRetry = async (retries, delayMs) => {
    try {
        const tab = await getActiveTab();
        const url = tab?.url ?? null;
        if (url) {
            const ok = await saveUrl(url);
            setTimeout(() => window.close(), ok ? 1800 : 2600);
            return;
        }
    } catch (error) {
        setStatus(error?.message ?? "Save failed.");
        setTimeout(() => window.close(), 2600);
        return;
    }
    if (retries <= 0) {
        setStatus("No active tab URL.");
        setTimeout(() => window.close(), 2600);
        return;
    }
    setStatus("Loading tab...");
    setTimeout(() => {
        saveWithRetry(retries - 1, delayMs);
    }, delayMs);
};

document.addEventListener("DOMContentLoaded", () => {
    saveWithRetry(12, 150);
});
