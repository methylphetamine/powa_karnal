(() => {
  const listEl = document.getElementById("release-list");
  const emptyEl = document.getElementById("empty-state");
  const errorEl = document.getElementById("error-state");
  const errorDetail = document.getElementById("error-detail");
  const stampEl = document.getElementById("build-stamp");
  const filtersEl = document.getElementById("filters");
  const template = document.getElementById("release-template");

  let releases = [];
  let activeFilter = "all";

  const DATE_FMT = new Intl.DateTimeFormat(undefined, {
    year: "numeric",
    month: "short",
    day: "numeric",
  });

  function formatDate(value) {
    if (!value) return "—";
    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? "—" : DATE_FMT.format(date);
  }

  function formatSize(bytes) {
    if (!Number.isFinite(bytes) || bytes <= 0) return "—";
    const units = ["B", "KiB", "MiB", "GiB"];
    let value = bytes;
    let unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit += 1;
    }
    return `${value >= 10 || unit === 0 ? Math.round(value) : value.toFixed(1)} ${units[unit]}`;
  }

  function rootOf(release) {
    const raw = (release.variant || release.tag || release.name || "").toLowerCase();
    if (raw.includes("folkpatch")) return "folkpatch";
    if (raw.includes("apatch") || raw.includes("sultan")) return "apatch";
    if (raw.includes("ksu") || raw.includes("kernelsu")) return "ksu";
    if (raw.includes("vanilla")) return "vanilla";
    return "other";
  }

  function rootLabel(root) {
    return {
      ksu: "KSU",
      apatch: "APatch",
      folkpatch: "FolkPatch",
      vanilla: "Vanilla",
      other: "Build",
    }[root] || "Build";
  }

  function overlaysOf(release) {
    const raw = (release.variant || release.tag || release.name || "").toLowerCase();
    const out = [];
    if (raw.includes("c2") || raw.includes("codec2")) out.push("Codec2");
    if (raw.includes("miui") || raw.includes("hyperos")) out.push("MIUI");
    return out;
  }

  function zipAsset(release) {
    return (release.assets || []).find((asset) => /\.zip$/i.test(asset.name || ""));
  }

  function downloadTarget(release) {
    if (release.mirror) return { url: release.mirror, label: "Download mirror", external: true };
    const asset = zipAsset(release);
    if (asset && asset.url) {
      return { url: asset.url, label: "Download zip", external: true, auth: true };
    }
    if (release.html_url) return { url: release.html_url, label: "Open release", external: true, auth: true };
    return null;
  }

  function makeTag(text, className) {
    const span = document.createElement("span");
    span.className = className;
    span.textContent = text;
    return span;
  }

  function renderCard(release, isLatest) {
    const node = template.content.firstElementChild.cloneNode(true);
    const root = rootOf(release);

    node.querySelector("h3").textContent = release.name || release.title || release.tag;
    node.querySelector(".release-sub").textContent = release.title && release.title !== release.name
      ? release.title
      : release.tag;

    const latestBadge = node.querySelector(".badge-latest");
    latestBadge.hidden = !isLatest;

    const chips = node.querySelector(".release-chips");
    chips.appendChild(makeTag(rootLabel(root), `tag root-${root}`));
    overlaysOf(release).forEach((overlay) => {
      chips.appendChild(makeTag(overlay, "tag overlay"));
    });
    if (release.prerelease) chips.appendChild(makeTag("Pre-release", "tag"));

    node.querySelector('[data-field="kernel"]').textContent = release.kernel || "—";
    node.querySelector('[data-field="commit"]').textContent = release.commit || "—";
    node.querySelector('[data-field="date"]').textContent = formatDate(release.published_at);
    node.querySelector('[data-field="size"]').textContent = formatSize(zipAsset(release)?.size);
    node.querySelector('[data-field="size"]').title = zipAsset(release)?.name || "";

    const shaWrap = node.querySelector('[data-field="sha-wrap"]');
    const shaEl = node.querySelector('[data-field="sha"]');
    if (release.sha256) {
      shaEl.textContent = release.sha256;
      shaEl.title = release.sha256;
      const copyBtn = node.querySelector("[data-copy]");
      copyBtn.addEventListener("click", async () => {
        try {
          await navigator.clipboard.writeText(release.sha256);
          copyBtn.textContent = "Copied";
          setTimeout(() => { copyBtn.textContent = "Copy"; }, 1400);
        } catch {
          copyBtn.textContent = "Failed";
          setTimeout(() => { copyBtn.textContent = "Copy"; }, 1400);
        }
      });
    } else {
      shaWrap.hidden = true;
    }

    const download = node.querySelector("[data-download]");
    const target = downloadTarget(release);
    if (target) {
      download.href = target.url;
      download.textContent = target.label;
      if (target.auth) {
        download.title = "This build lives on GitHub; a repository account may be required.";
      }
    } else {
      download.setAttribute("aria-disabled", "true");
      download.textContent = "Unavailable";
      download.removeAttribute("href");
    }

    const notes = node.querySelector("[data-notes]");
    if (release.html_url) {
      notes.href = release.html_url;
    } else {
      notes.hidden = true;
    }

    return node;
  }

  function render() {
    const visible = activeFilter === "all"
      ? releases
      : releases.filter((release) => rootOf(release) === activeFilter);

    listEl.replaceChildren();
    emptyEl.hidden = releases.length !== 0 || visible.length !== 0;

    if (!visible.length) {
      if (releases.length) {
        emptyEl.hidden = false;
        emptyEl.querySelector("h3").textContent = "No builds for this root yet";
        emptyEl.querySelector("p").textContent =
          "Try another filter, or check back after the next workflow run.";
      }
      return;
    }

    const latestIndex = releases.findIndex((release) => !release.prerelease);
    visible.forEach((release) => {
      listEl.appendChild(renderCard(release, releases.indexOf(release) === latestIndex));
    });
  }

  function setStamp(payload) {
    const when = payload.generated_at ? formatDate(payload.generated_at) : null;
    const count = releases.length;
    if (!count) {
      stampEl.textContent = when ? `Release index updated ${when}` : "";
      return;
    }
    stampEl.textContent = `${count} build${count === 1 ? "" : "s"}${when ? ` · updated ${when}` : ""}`;
  }

  function showError(error) {
    errorEl.hidden = false;
    errorDetail.textContent = String(error?.message || error);
    stampEl.textContent = "";
  }

  async function load() {
    const response = await fetch(`releases.json?t=${Date.now()}`, { cache: "no-store" });
    if (!response.ok) throw new Error(`releases.json returned HTTP ${response.status}`);
    const payload = await response.json();
    releases = Array.isArray(payload.releases) ? payload.releases : [];
    setStamp(payload);
    render();
  }

  filtersEl.addEventListener("click", (event) => {
    const button = event.target.closest("[data-filter]");
    if (!button) return;
    activeFilter = button.dataset.filter;
    filtersEl.querySelectorAll("[data-filter]").forEach((chip) => {
      chip.classList.toggle("is-active", chip === button);
    });
    render();
  });

  load().catch((error) => {
    showError(error);
    emptyEl.hidden = true;
  });
})();
