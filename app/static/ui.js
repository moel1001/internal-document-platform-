const form = document.getElementById("docForm");
const result = document.getElementById("result");
const curl = document.getElementById("curl");
const copyCurlBtn = document.getElementById("copyCurlBtn");
let lastCurlText = "";

const exampleBtn = document.getElementById("exampleBtn");
const badExampleBtn = document.getElementById("badExampleBtn");

const loadValidBtn = document.getElementById("loadValidBtn");
const loadInvalidBtn = document.getElementById("loadInvalidBtn");
const stopLoadBtn = document.getElementById("stopLoadBtn");
const loadCountEl = document.getElementById("loadCount");
const loadStatus = document.getElementById("loadStatus");

stopLoadBtn.disabled = true;

const allowedTypes = ["invoice", "delivery_note", "certificate"];
const sourceSystems = [
  "sap",
  "oracle-erp",
  "d365",
  "workday",
  "navision",
  "custom-erp",
];

let lastExampleKey = null;
let loadAbort = { stop: false };

function randInt(min, max) {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

function choice(arr) {
  return arr[randInt(0, arr.length - 1)];
}

function randomDateISO(daysBack = 90) {
  const d = new Date();
  d.setDate(d.getDate() - randInt(0, daysBack));
  return d.toISOString().slice(0, 10);
}

function pad(n, width = 4) {
  return String(n).padStart(width, "0");
}

function buildPayloadFromForm() {
  return {
    document_id: document.getElementById("document_id").value.trim(),
    document_type: document.getElementById("document_type").value,
    created_at: document.getElementById("created_at").value,
    source_system: document.getElementById("source_system").value.trim(),
  };
}

function updateCurl(payload) {
  const base =
    window.location.protocol === "https:"
      ? `http://${window.location.host}`
      : window.location.origin;

  const prettyJson = JSON.stringify(payload, null, 2)
    .split("\n")
    .map((line) => "      " + line)
    .join("\n");

  lastCurlText = `curl -s -X POST ${base}/validate \\
  -H "Content-Type: application/json" \\
  -d '\
${prettyJson}
  ' | jq`;

  curl.textContent = "$ " + lastCurlText;
}

copyCurlBtn.addEventListener("click", async () => {
  const originalText = copyCurlBtn.textContent;

  try {
    const textToCopy = lastCurlText;
    await navigator.clipboard.writeText(textToCopy);

    copyCurlBtn.textContent = "✅ Copied";
    copyCurlBtn.disabled = true;

    setTimeout(() => {
      copyCurlBtn.textContent = originalText;
      copyCurlBtn.disabled = false;
    }, 1200);
  } catch (e) {
    copyCurlBtn.textContent = "Copy failed";
    copyCurlBtn.disabled = true;

    setTimeout(() => {
      copyCurlBtn.textContent = originalText;
      copyCurlBtn.disabled = false;
    }, 1600);
  }
});

function setDocumentType(value) {
  const sel = document.getElementById("document_type");
  if (![...sel.options].some((o) => o.value === value)) {
    const opt = document.createElement("option");
    opt.value = value;
    opt.textContent = value === "" ? "-- select --" : value;
    sel.appendChild(opt);
  }
  sel.value = value;
}

function applyToForm(payload) {
  document.getElementById("document_id").value = payload.document_id;
  setDocumentType(payload.document_type);
  document.getElementById("created_at").value = payload.created_at;
  document.getElementById("source_system").value = payload.source_system;
  updateCurl(payload);
}

function makeValidExample() {
  const t = choice(allowedTypes);
  const sys = choice(sourceSystems);
  const date = randomDateISO(120);
  const prefix =
    t === "invoice" ? "INV" : t === "delivery_note" ? "DN" : "CERT";
  const id = `${prefix}-${new Date().getFullYear()}-${pad(randInt(1, 9999))}`;

  return {
    document_id: id,
    document_type: t,
    created_at: date,
    source_system: sys,
  };
}

function makeInvalidExample() {
  const kind = choice([
    "EMPTY_ID",
    "EMPTY_DATE",
    "EMPTY_SOURCE",
    "EMPTY_TYPE",
    "INVALID_TYPE",
  ]);

  const base = makeValidExample();

  if (kind === "EMPTY_ID") base.document_id = "   ";
  else if (kind === "EMPTY_DATE") base.created_at = "";
  else if (kind === "EMPTY_SOURCE") base.source_system = "   ";
  else if (kind === "EMPTY_TYPE") base.document_type = "";
  else if (kind === "INVALID_TYPE")
    base.document_type = choice([
      "credit_note",
      "invoicee",
      "unknown_type",
      "receipt",
      "invoice-v2",
    ]);

  return base;
}

function generateDifferent(generatorFn) {
  for (let i = 0; i < 8; i++) {
    const p = generatorFn();
    const key = JSON.stringify(p);
    if (key !== lastExampleKey) {
      lastExampleKey = key;
      return p;
    }
  }
  const p = generatorFn();
  lastExampleKey = JSON.stringify(p);
  return p;
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function runLoad({ count, mode }) {
  loadValidBtn.disabled = true;
  loadInvalidBtn.disabled = true;
  stopLoadBtn.disabled = false;
  loadAbort.stop = false;

  let ok = 0;
  let rejected = 0;
  let errors = 0;

  const start = Date.now();
  loadStatus.textContent = `Starting ${count} requests (${mode})…`;

  for (let i = 1; i <= count; i++) {
    if (loadAbort.stop) break;

    const payload =
      mode === "valid" ? makeValidExample() : makeInvalidExample();

    try {
      const res = await fetch("/validate", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      });

      if (!res.ok) {
        errors++;
      } else {
        const data = await res.json();
        if (data.status === "ACCEPTED") ok++;
        else rejected++;
      }
    } catch (e) {
      errors++;
    }

    if (i % 10 === 0 || i === count) {
      const elapsed = ((Date.now() - start) / 1000).toFixed(1);
      loadStatus.textContent =
        `Progress: ${i}/${count}\n` +
        `ACCEPTED: ${ok}\nREJECTED: ${rejected}\nHTTP/JS errors: ${errors}\n` +
        `Elapsed: ${elapsed}s`;
    }

    await sleep(10);
  }

  const elapsed = ((Date.now() - start) / 1000).toFixed(1);
  const stopped = loadAbort.stop ? " (stopped)" : "";
  loadStatus.textContent =
    `Done${stopped}\n` +
    `ACCEPTED: ${ok}\nREJECTED: ${rejected}\nHTTP/JS errors: ${errors}\n` +
    `Elapsed: ${elapsed}s`;

  loadStatus.classList.remove("highlight-finish");
  void loadStatus.offsetWidth;
  loadStatus.classList.add("highlight-finish");

  loadValidBtn.disabled = false;
  loadInvalidBtn.disabled = false;
  stopLoadBtn.disabled = true;

  loadStatus.scrollIntoView({ behavior: "smooth", block: "center" });
}

exampleBtn.addEventListener("click", () => {
  const payload = generateDifferent(makeValidExample);
  applyToForm(payload);
});

badExampleBtn.addEventListener("click", () => {
  const payload = generateDifferent(makeInvalidExample);
  applyToForm(payload);
});

function getValidatedLoadCount() {
  const raw = parseInt(loadCountEl.value, 10);

  if (isNaN(raw)) {
    loadStatus.textContent = "Load requests must be a number.";
    loadStatus.style.color = "red";
    return null;
  }

  if (raw < 1) {
    loadStatus.textContent = "Load requests must be >= 1.";
    loadStatus.style.color = "red";
    return null;
  }

  if (raw > 5000) {
    loadStatus.textContent = "Load requests must be <= 5000.";
    loadStatus.style.color = "red";
    return null;
  }

  loadStatus.style.color = "";
  return raw;
}

loadValidBtn.addEventListener("click", async () => {
  const count = getValidatedLoadCount();
  if (!count) return;

  await runLoad({ count, mode: "valid" });
});

loadInvalidBtn.addEventListener("click", async () => {
  const count = getValidatedLoadCount();
  if (!count) return;

  await runLoad({ count, mode: "invalid" });
});

stopLoadBtn.addEventListener("click", () => {
  loadAbort.stop = true;
});

form.addEventListener("submit", async (e) => {
  e.preventDefault();
  const payload = buildPayloadFromForm();
  updateCurl(payload);

  result.className = "status-loading fade-in";
  result.textContent = "🟡 Sending request…";

  await new Promise((r) => setTimeout(r, 300));

  try {
    const res = await fetch("/validate", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });

    const data = await res.json();

    const formatted = JSON.stringify(
      { http_status: res.status, response: data },
      null,
      2,
    );

    if (data.status === "ACCEPTED") {
      result.className = "status-success fade-in";
      result.textContent = "🟢 Document ACCEPTED\n\n" + formatted;
    } else {
      result.className = "status-error fade-in";
      result.textContent = "🔴 Document REJECTED\n\n" + formatted;
    }
  } catch (err) {
    result.className = "status-error fade-in";
    result.textContent = "⚠️ Request failed: " + err;
  }
});

const initial = makeValidExample();
lastExampleKey = JSON.stringify(initial);
applyToForm(initial);
