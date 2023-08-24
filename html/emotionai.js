
window.resolver = null;
window.pauseWork = null;
window.resumeWork = null;

const customSource = {
  // The getFrame methods must return a promise resolved with the ImageData of the currentFrame.
  // It currently retrieves the frame from the Native App getFrameFromApp method encoded in Base64
  // maxSize = Max size in px of the larger side of the frame. You should scale the image yourself before resolving it (optional).

  getFrame(maxSize) {
    return new Promise((resolve) => {
      RequestFrame.postMessage(maxSize);
      window.resolver = resolve;
    });
  },
  start() {
  },
  stop() {
  },
}

function loadEmotionAI(emotionaiKey) {
  CY.loader()
    .licenseKey(emotionaiKey)
    .addModule(CY.modules().FACE_AROUSAL_VALENCE.name, { smoothness: 0.3 })
    .source(customSource)
    .powerSave(0.3)
    .load()
    .then(({ start, stop }) => {
      window.pauseWork = stop;
      window.resumeWork = start;
      start()
    });
}

function pauseEmotionAI() {
  if (window.pauseWork) {
    window.pauseWork();
  }
}

function resumeEmotionAI() {
  if (window.resumeWork) {
    window.resumeWork();
  }
}

window.addEventListener('CY_FACE_AROUSAL_VALENCE_RESULT', function(data) {
  if (data) {
    ArousalValence.postMessage(JSON.stringify(data.detail.output));
  }
});

function useResolver(b64) {
  if (resolver == null) {
    console.log('ERROR: RESOLVER IS NULL');
    return;
  }
  var canvas = document.createElement('canvas');
  var context = canvas.getContext('2d', { willReadFrequently: true });
  var img = new Image();
  img.onload = function() {
    canvas.width = img.width;
    canvas.height = img.height;
    context.drawImage(img, 0, 0);
    resolver(context.getImageData(0, 0, img.width, img.height));
    resolver = null;
  };
  img.src = `data:image/jpeg;base64,${b64}`;
}

EmotionAIKeyRequest.postMessage('ready');

