const saveButton = document.getElementById("saveButton");
const status = document.getElementById("status");

const setStatus = (text) => {
    status.textContent = text;
};

const getActiveTab = async () => {
    const tabs = await browser.tabs.query({ active: true, currentWindow: true });
    return tabs && tabs[0] ? tabs[0] : null;
};

const showToast = async () => {
    try {
        const tab = await getActiveTab();
        if (!tab || !tab.id)
            return;
        await browser.tabs.sendMessage(tab.id, {
            action: "show_toast",
            text: "Saved to sideBar"
        });
    } catch (error) {
        // Ignore toast errors.
    }
};

const saveUrl = async (url) => {
    const response = await browser.runtime.sendNativeMessage({
        action: "save_url",
        url
    });
    if (response && response.ok) {
        setStatus("Saved for later.");
        await showToast();
        return true;
    }
    setStatus(response?.error ?? "Save failed.");
    return false;
};

const saveCurrentTab = async () => {
    if (saveButton)
        saveButton.disabled = true;
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
    } finally {
        if (saveButton)
            saveButton.disabled = false;
    }
};

const saveWithRetry = async (retries, delayMs) => {
    try {
        const tab = await getActiveTab();
        const url = tab?.url ?? null;
        if (url) {
            const ok = await saveUrl(url);
            if (ok)
                setTimeout(() => window.close(), 300);
            return;
        }
    } catch (error) {
        setStatus(error?.message ?? "Save failed.");
        return;
    }
    if (retries <= 0) {
        setStatus("No active tab URL.");
        return;
    }
    setStatus("Loading tab...");
    setTimeout(() => {
        saveWithRetry(retries - 1, delayMs);
    }, delayMs);
};

if (saveButton) {
    saveButton.addEventListener("click", async () => {
        const ok = await saveCurrentTab();
        if (ok)
            setTimeout(() => window.close(), 300);
    });
}

document.addEventListener("DOMContentLoaded", () => {
    saveWithRetry(12, 150);
});
