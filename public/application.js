function clickDelete(event) {
  const filename = this.getAttribute("data-filename");
  const imageContainer = event.target.parentNode.closest("div.i-c");

  deleteImage(filename, imageContainer);
  event.stopPropagation();
}

function deleteImage(filename, imageContainer) {
  if (!confirm("Are you sure you want to delete this image?")) {
    return;
  }
  const xhr = new XMLHttpRequest();

  xhr.open("DELETE", "/image/" + filename, true);

  xhr.onload = function () {
    if (xhr.status === 200) {
      // Remove the image container from the DOM
      zoomPrev();
      imageContainer.parentNode.removeChild(imageContainer);
    } else {
      alert("Error deleting image");
    }
  };
  xhr.send();
}

function toggleZoom() {
  this.classList.toggle("zoomed");
}

function zoomNext(event) {
  const zoomed = document.querySelector(".zoomed");
  if (zoomed) {
    const next = zoomed.nextElementSibling;
    if (next) {
      zoom(next);
    } 
  }
  if( event ) {
    event.stopPropagation()
  }
}

function zoomPrev(event) {
  const zoomed = document.querySelector(".zoomed");
  if (zoomed) {
    const prev = zoomed.previousElementSibling;
    if (prev) {
      zoom(prev);
    }
  }
  if( event ) {
    event.stopPropagation()
  }
}

function createImageNodes(images) {
  const newImage = document.createElement("div");
  newImage.innerHTML = images;
  // add event listener to the new delete button
  newImage.querySelectorAll(".delete-btn").forEach(function (button) {
    button.addEventListener("click", clickDelete);
  });
  newImage.querySelectorAll("img").forEach(function (img) {
    img.parentElement.addEventListener("click", toggleZoom);
    img.addEventListener("load", function () {
      // Access the natural width and height of the image
      const width = img.naturalWidth;
      const height = img.naturalHeight;

      // Display the dimensions
      const dimensionsDisplay = img.parentElement.querySelector(".dimensions");
      dimensionsDisplay.textContent = `${width} x ${height}`;
    });
  });
  newImage.querySelectorAll(".load-prompt-btn").forEach(function (button) {
    button.addEventListener("click", function (event) {
      const prompt = button.parentElement.parentElement 
        .querySelector(".prompt p").textContent
      document.getElementById("prompt").value = prompt;
      zoom();
      if( event ) {
        event.stopPropagation()
      }
      scrollTo(0, 0);
    });
  });
  newImage.querySelectorAll(".upscale-btn").forEach(function (button) {
    button.addEventListener("click", upscaleImage);
  });
  newImage.querySelectorAll(".next-btn").forEach(function (button) {
    button.addEventListener("click", zoomNext );
  });
  newImage.querySelectorAll(".previous-btn").forEach(function (button) {
    button.addEventListener("click", zoomPrev );
  });
  return newImage.childNodes;
}

function submitGenerationForm(event) {
  event.preventDefault();

  const formData = new FormData(this);
  const prompt = formData.get("prompt");
  const xhr = new XMLHttpRequest();
  xhr.open("POST", "/generate", true);
  xhr.setRequestHeader("Accept", "application/json");

  const resultDiv = document.getElementById("result");

  const placeholder = document.createElement("div");
  placeholder.classList.add("i-c");
  placeholder.innerHTML = `<div class='proxy bg-animated'><div class='ripple'></div><p class='prompt'>${prompt}</p></div>`;
  

  xhr.onload = function () {
    if (xhr.status === 200) {
      // remove the placeholder div and add the generated image
      resultDiv.removeChild(placeholder);
      resultDiv.prepend(...createImageNodes(xhr.responseText));
    } else {
      alert("Error generating image: " + xhr.responseText);
    }
  };
  // add a placeholder div to the result div and start a spinner inside it
  resultDiv.prepend(placeholder);

  xhr.send(formData);
}

// Enhance Prompt
function enhancePrompt(event) {
  event.preventDefault();
  const xhr = new XMLHttpRequest();
  const prompt = document.getElementById("prompt");

  xhr.open("POST", "/enhance_prompt", true);
  xhr.setRequestHeader("Accept", "application/json");
  xhr.setRequestHeader("Content-Type", "application/json");
  prompt.classList.add("bg-animated");

  xhr.onload = function () {
    prompt.classList.remove("bg-animated");
    if (xhr.status === 200) {
      prompt.value = JSON.parse(xhr.responseText).enhanced_prompt;
    } else {
      alert("Error enhancing prompt: " + xhr.responseText);
    }
  };

  xhr.send(JSON.stringify({ prompt: prompt.value }));
}

function upscaleImage(event) {
  event.preventDefault();
  const xhr = new XMLHttpRequest();
  const filename = this.getAttribute("data-filename");

  xhr.open("POST", "/upscale/" + filename, true);
  xhr.setRequestHeader("Accept", "application/json");
  xhr.setRequestHeader("Content-Type", "application/json");

  xhr.onload = function () {
    if (xhr.status === 200) {
      const resultDiv = document.getElementById("result");
      resultDiv.prepend(...createImageNodes(xhr.responseText));
    } else {
      alert("Error upscaling image: " + xhr.responseText);
    }
  };

  xhr.send();
}

// Load more images
function loadMore( onloadHandler ) {
  const xhr = new XMLHttpRequest();

  const lastImage = document.querySelector("#result div:last-child img");
  const fileName = lastImage
    ? lastImage.getAttribute("src").split("/").pop()
    : null;
  xhr.open("GET", "/images?filename=" + fileName, true);
  xhr.setRequestHeader("Accept", "application/json");

  xhr.onload = function () {
    if (xhr.status === 200) {
      const resultDiv = document.getElementById("result");
      resultDiv.append(...createImageNodes(xhr.responseText));
    } else {
      alert("Error loading more images: " + xhr.responseText);
    }
  };

  xhr.send();
}

window.onload = function () {
  loadMore();
  document
    .getElementById("imageForm")
    .addEventListener("submit", submitGenerationForm);
  document.getElementById("loadMore").addEventListener("click", loadMore);
  document
    .getElementById("enhancePrompt")
    .addEventListener("click", enhancePrompt);
};

function zoom(elt) {
  const zoomed = document.querySelector(".zoomed");
  if (zoomed) {
    zoomed.classList.remove("zoomed");
  }

  if( elt ) {
      elt.classList.toggle("zoomed");
  }
}

// on cursor right, move zoomed class to the next picture
document.onkeydown = function (e) {
  e = e || window.event;
  if (e.keyCode == "39") {
    zoomNext();
    }
    if (e.keyCode == "37") {
    zoomPrev();
    }
    // esc key to remove zoomed class
    if (e.keyCode == "27") {
        zoom();
    }
    // x key trigger delete if zoomed
    if (e.keyCode == "88") {
        const zoomed = document.querySelector(".zoomed");
        if (zoomed) {
            const filename = zoomed.querySelector("img").getAttribute("src").split("/").pop();
            const imageContainer = zoomed.closest("div.i-c");
            deleteImage(filename, imageContainer);
        }
    }
  }
