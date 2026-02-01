const ensureToastContainer = () => {
    const existing = document.getElementById("sidebar-safari-toast-container");
    if (existing)
        return existing;
    const container = document.createElement("div");
    container.id = "sidebar-safari-toast-container";
    container.style.position = "fixed";
    container.style.top = "16px";
    container.style.right = "16px";
    container.style.zIndex = "2147483647";
    container.style.pointerEvents = "none";
    document.documentElement.appendChild(container);
    return container;
};

const showToast = (message) => {
    const container = ensureToastContainer();
    const toast = document.createElement("div");
    toast.textContent = message;
    toast.style.background = "rgba(28, 28, 30, 0.92)";
    toast.style.color = "#ffffff";
    toast.style.fontFamily = "-apple-system, BlinkMacSystemFont, \"Segoe UI\", sans-serif";
    toast.style.fontSize = "14px";
    toast.style.fontWeight = "600";
    toast.style.padding = "10px 14px";
    toast.style.borderRadius = "12px";
    toast.style.boxShadow = "0 6px 18px rgba(0,0,0,0.2)";
    toast.style.opacity = "0";
    toast.style.transform = "translateY(-8px)";
    toast.style.transition = "opacity 0.18s ease, transform 0.18s ease";
    toast.style.marginBottom = "8px";
    container.appendChild(toast);
    requestAnimationFrame(() => {
        toast.style.opacity = "1";
        toast.style.transform = "translateY(0)";
    });
    setTimeout(() => {
        toast.style.opacity = "0";
        toast.style.transform = "translateY(-8px)";
        setTimeout(() => {
            toast.remove();
        }, 220);
    }, 1500);
};

browser.runtime.onMessage.addListener((message) => {
    if (message?.action === "show_toast") {
        showToast(message.text || "Saved to sideBar");
    }
});
