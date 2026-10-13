chrome.runtime.sendMessage("status", (status) => {
  document.getElementById("out").textContent = JSON.stringify(status, null, 2);
});
