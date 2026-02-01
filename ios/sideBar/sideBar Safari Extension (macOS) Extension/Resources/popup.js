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

saveButton.addEventListener("click", async () => {
    saveButton.disabled = true;
    setStatus("Saving...");
    try {
        const url = await getActiveTabUrl();
        if (!url) {
            setStatus("No active tab URL.");
            return;
        }
        const response = await browser.runtime.sendNativeMessage({
            action: "save_url",
            url
        });
        if (response && response.ok) {
            setStatus("Saved for later.");
        } else {
            setStatus(response?.error ?? "Save failed.");
        }
    } catch (error) {
        setStatus("Save failed.");
        console.error(error);
    } finally {
        saveButton.disabled = false;
    }
});
