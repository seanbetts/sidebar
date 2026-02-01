const saveButton = document.getElementById("saveButton");
const status = document.getElementById("status");

const setStatus = (text) => {
    status.textContent = text;
};

const getActiveTabUrl = async () => {
    const tabs = await browser.tabs.query({ active: true, currentWindow: true });
    const tab = tabs && tabs[0];
    return tab ? tab.url : null;
};

const saveUrl = async (url) => {
    const response = await browser.runtime.sendNativeMessage({
        action: "save_url",
        url
    });
    if (response && response.ok) {
        setStatus("Saved for later.");
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
        const url = await getActiveTabUrl();
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
        const url = await getActiveTabUrl();
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
