# shellcheck shell=bash
# Fetch MOSAiC AYIL Zenodo input bundle on demand (not at install).
#
# Record: https://zenodo.org/records/10491362
# File:   ayil_config_input_results.zip (~870 MiB) -> ayil_config_input_results/YYYYMMDD/
#
# Git tracks per-day namoptions (pipeline edits, e.g. trestart=-1). Install uses
# rsync --ignore-existing so Zenodo never overwrites files already in the tree;
# only missing artifacts are added (NetCDF, prof.inp.*, *.001, etc.).
#
# Source after config.sh. Set AYIL_SKIP_ZENODO_FETCH=1 to disable network fetch.

: "${MOSAiC_AYIL_ROOT:?MOSAiC_AYIL_ROOT required}"
: "${AYIL_INPUTS:?AYIL_INPUTS required}"

AYIL_ZENODO_RECORD="${AYIL_ZENODO_RECORD:-10491362}"
AYIL_ZENODO_INPUT_ZIP="${AYIL_ZENODO_INPUT_ZIP:-ayil_config_input_results.zip}"
AYIL_ZENODO_CACHE="${AYIL_ZENODO_CACHE:-${MOSAiC_AYIL_ROOT}/.cache/zenodo}"
AYIL_ZENODO_URL="${AYIL_ZENODO_URL:-https://zenodo.org/records/${AYIL_ZENODO_RECORD}/files/${AYIL_ZENODO_INPUT_ZIP}?download=1}"
AYIL_ZENODO_MARKER="${AYIL_INPUTS}/.zenodo_bundle_installed"

_ayil_log() {
  echo "[ayil-zenodo] $*"
}

# True when one day has the files prepare_case needs.
ayil_day_inputs_ready() {
  local date="$1"
  local day_dir="${AYIL_INPUTS}/${date}"
  [[ -f "${day_dir}/namoptions" ]] \
    && [[ -f "${day_dir}/scm_in.a_year_in_les.${date}.nc" ]]
}

# True when the full Zenodo bundle appears installed (sample day + marker).
ayil_zenodo_bundle_ready() {
  [[ -f "${AYIL_ZENODO_MARKER}" ]] && ayil_day_inputs_ready "20200720"
}

_ayil_download_url() {
  local dest="$1"
  local url="$2"
  mkdir -p "$(dirname "${dest}")"
  if command -v curl &>/dev/null; then
    curl -fL --retry 3 --retry-delay 5 -C - -o "${dest}" "${url}"
    return
  fi
  if command -v wget &>/dev/null; then
    wget -c -O "${dest}" "${url}"
    return
  fi
  echo "ERROR: need curl or wget to download Zenodo inputs" >&2
  return 1
}

# Download zip (cached) and extract into AYIL_INPUTS.
ayil_ensure_zenodo_bundle() {
  if ayil_zenodo_bundle_ready; then
    return 0
  fi
  if [[ "${AYIL_SKIP_ZENODO_FETCH:-0}" == "1" ]]; then
    echo "ERROR: Zenodo inputs missing under ${AYIL_INPUTS} and AYIL_SKIP_ZENODO_FETCH=1" >&2
    echo "  Unzip ${AYIL_ZENODO_INPUT_ZIP} into ${AYIL_INPUTS} or unset AYIL_SKIP_ZENODO_FETCH." >&2
    return 1
  fi

  local zip_path="${AYIL_ZENODO_CACHE}/${AYIL_ZENODO_INPUT_ZIP}"
  mkdir -p "${AYIL_ZENODO_CACHE}" "${AYIL_INPUTS}"

  if [[ ! -f "${zip_path}" ]]; then
    _ayil_log "Downloading ${AYIL_ZENODO_INPUT_ZIP} from Zenodo record ${AYIL_ZENODO_RECORD} ..."
    _ayil_log "URL: ${AYIL_ZENODO_URL}"
    _ayil_log "Cache: ${zip_path}"
    _ayil_download_url "${zip_path}" "${AYIL_ZENODO_URL}"
  else
    _ayil_log "Using cached zip ${zip_path}"
  fi

  local tmp src
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/ayil_zenodo.XXXXXX")"

  _ayil_log "Extracting (this may take a few minutes) ..."
  if ! unzip -q "${zip_path}" -d "${tmp}"; then
    rm -rf "${tmp}"
    echo "ERROR: unzip failed for ${zip_path}" >&2
    return 1
  fi

  if [[ -d "${tmp}/ayil_config_input_results" ]]; then
    src="${tmp}/ayil_config_input_results"
  elif compgen -G "${tmp}/20??????" >/dev/null; then
    src="${tmp}"
  else
    echo "ERROR: could not find day folders inside ${AYIL_ZENODO_INPUT_ZIP}" >&2
    find "${tmp}" -maxdepth 2 -type d | head -20 >&2 || true
    rm -rf "${tmp}"
    return 1
  fi

  _ayil_log "Installing inputs from ${src} -> ${AYIL_INPUTS}"
  _ayil_log "rsync --ignore-existing (keeps tracked/edited namoptions and other present files)"
  rsync -a --ignore-existing "${src}/" "${AYIL_INPUTS}/"
  rm -rf "${tmp}"

  {
    echo "record=${AYIL_ZENODO_RECORD}"
    echo "zip=${AYIL_ZENODO_INPUT_ZIP}"
    echo "url=${AYIL_ZENODO_URL}"
    echo "rsync=ignore-existing"
    echo "installed_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } > "${AYIL_ZENODO_MARKER}"

  if ! ayil_zenodo_bundle_ready; then
    echo "ERROR: extract finished but sample day ${AYIL_INPUTS}/20200720 is incomplete" >&2
    return 1
  fi
  _ayil_log "Zenodo inputs ready under ${AYIL_INPUTS}"
}

# Ensure one day's input folder exists (download full bundle on first use).
ayil_ensure_day_inputs() {
  local date="$1"
  if ayil_day_inputs_ready "${date}"; then
    return 0
  fi
  ayil_ensure_zenodo_bundle
  if ayil_day_inputs_ready "${date}"; then
    return 0
  fi
  echo "ERROR: no inputs for ${date} under ${AYIL_INPUTS} after Zenodo install" >&2
  return 1
}
