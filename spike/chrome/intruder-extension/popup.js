chrome.runtime.sendMessage("try", (r) => {
  document.getElementById("out").textContent = JSON.stringify(r, null, 2);
});
