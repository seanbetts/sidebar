const status = document.getElementById("status");
const STATUS_TONES = ["tone-pending", "tone-success", "tone-error"];

const setStatus = (text, tone = "pending") => {
    STATUS_TONES.forEach((className) => status.classList.remove(className));
    status.classList.add(`tone-${tone}`);
    status.textContent = text;
};

const CODE_TO_MESSAGE = {
    saved_for_later: "Saved for later.",
    unsupported_action: "This action is not supported.",
    missing_url: "No active tab URL found.",
    invalid_url: "That URL is invalid.",
    no_active_url: "No active tab URL found.",
    queue_failed: "Could not save for later.",
    not_authenticated: "Please sign in to sideBar first.",
    network_error: "Network error. Please try again.",
    unknown_failure: "Something went wrong. Please try again."
};

const messageFromResponse = (response, fallbackCode = "unknown_failure") => {
    const responseCode = typeof response?.code === "string" ? response.code : fallbackCode;
    return CODE_TO_MESSAGE[responseCode] ?? CODE_TO_MESSAGE.unknown_failure;
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
        setStatus(messageFromResponse(response, "saved_for_later"), "success");
        return true;
    }
    setStatus(messageFromResponse(response), "error");
    return false;
};

const saveCurrentTab = async () => {
    setStatus("Saving...", "pending");
    try {
        const tab = await getActiveTab();
        const url = tab?.url ?? null;
        if (!url) {
            setStatus(CODE_TO_MESSAGE.no_active_url, "error");
            return false;
        }
        return await saveUrl(url);
    } catch (_error) {
        setStatus(CODE_TO_MESSAGE.network_error, "error");
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
    } catch (_error) {
        setStatus(CODE_TO_MESSAGE.network_error, "error");
        setTimeout(() => window.close(), 2600);
        return;
    }
    if (retries <= 0) {
        setStatus(CODE_TO_MESSAGE.no_active_url, "error");
        setTimeout(() => window.close(), 2600);
        return;
    }
    setStatus("Loading tab...", "pending");
    setTimeout(() => {
        saveWithRetry(retries - 1, delayMs);
    }, delayMs);
};

document.addEventListener("DOMContentLoaded", () => {
    saveWithRetry(12, 150);
});
