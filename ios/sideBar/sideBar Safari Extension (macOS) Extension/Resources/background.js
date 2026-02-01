const getActiveTabUrl = async () => {
    const tabs = await browser.tabs.query({ active: true, currentWindow: true });
    const tab = tabs && tabs[0];
    return tab && tab.url ? tab.url : null;
};

const saveUrl = async (url) => {
    if (!url)
        return;
    try {
        await browser.runtime.sendNativeMessage({
            action: "save_url",
            url
        });
    } catch (error) {
        // Ignore errors to avoid interrupting the user.
    }
};

browser.action.onClicked.addListener(async (tab) => {
    const url = (tab && tab.url) ? tab.url : await getActiveTabUrl();
    await saveUrl(url);
});
