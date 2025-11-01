const CopyToClipboardHook = {
    mounted() {
      window.addEventListener("clipcopy", (event) => {
        if ("clipboard" in navigator) {
          const text = event.target.textContent;
          navigator.clipboard.writeText(text);
        }
      });
    }
  };
  
  export default CopyToClipboardHook;