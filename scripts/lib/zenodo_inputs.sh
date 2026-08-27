# shellcheck shell=bash
# Fetch MOSAiC AYiL Zenodo input bundle on demand (not at install).
#
# Record: https://zenodo.org/records/10491362
# File:   ayil_config_input_results.zip (~870 MiB) -> ayil_config_input_results/YYYYMMDD/
#
# Git tracks per-day namoptions (pipeline edits, e.g. trestart=-1). Install uses
# rsync --ignore-existing so Zenodo never overwrites files already in the tree;
# only missing artifacts are added (NetCDF, prof.inp.*, *.001, etc.).
#
# Source after config.sh. Set AYiL_SKIP_ZENODO_FETCH=1 to disable network fetch.

: "${MOSAiC_AYiL_ROOT:?MOSAiC_AYiL_ROOT required}"
: "${AYiL_INPUTS:?AYiL_INPUTS required}"

AYiL_ZENODO_RECORD="${AYiL_ZENODO_RECORD:-10491362}"
AYiL_ZENODO_INPUT_ZIP="${AYiL_ZENODO_INPUT_ZIP:-ayil_config_input_results.zip}"
AYiL_ZENODO_CACHE="${AYiL_ZENODO_CACHE:-${MOSAiC_AYiL_ROOT}/.cache/zenodo}"
AYiL_ZENODO_URL="${AYiL_ZENODO_URL:-https://zenodo.org/records/${AYiL_ZENODO_RECORD}/files/${AYiL_ZENODO_INPUT_ZIP}?download=1}"
AYiL_ZENODO_MARKER="${AYiL_INPUTS}/.zenodo_bundle_installed"

_ayil_log() {
  echo "[ayil-zenodo] $*"
}

# True when one day has the files prepare_case needs.
ayil_day_inputs_ready() {
  local date="$1"
  local day_dir="${AYiL_INPUTS}/${date}"
  [[ -f "${day_dir}/namoptions" ]] \
    && [[ -f "${day_dir}/scm_in.a_year_in_les.${date}.nc" ]]
}

# True when the full Zenodo bundle appears installed (sample day + marker).
ayil_zenodo_bundle_ready() {
  [[ -f "${AYiL_ZENODO_MARKER}" ]] && ayil_day_inputs_ready "20200720"
}

# Conda/base curl often lacks CA certs on HPC; prefer system curl and a known CA bundle.
_ayil_setup_curl_ca_bundle() {
  if [[ -n "${CURL_CA_BUNDLE:-}" && -f "${CURL_CA_BUNDLE}" ]]; then
    return 0
  fi
  if [[ -n "${SSL_CERT_FILE:-}" && -f "${SSL_CERT_FILE}" ]]; then
    export CURL_CA_BUNDLE="${SSL_CERT_FILE}"
    return 0
  fi
  local candidate
  for candidate in \
    /etc/pki/tls/certs/ca-bundle.crt \
    /etc/ssl/certs/ca-certificates.crt \
    /etc/ssl/ca-bundle.pem \
    /etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem; do
    if [[ -f "${candidate}" ]]; then
      export CURL_CA_BUNDLE="${candidate}"
      _ayil_log "Using CA bundle: ${CURL_CA_BUNDLE}"
      return 0
    fi
  done
  return 1
}

_ayil_curl_bin() {
  local c p
  for c in /usr/bin/curl; do
    if [[ -x "${c}" ]]; then
      echo "${c}"
      return 0
    fi
  done
  p="$(command -v curl 2>/dev/null || true)"
  if [[ -n "${p}" ]]; then
    if [[ -n "${CONDA_PREFIX:-}" && "${p}" == "${CONDA_PREFIX}/bin/curl" ]]; then
      _ayil_log "Skipping conda curl (${p}); use system curl or set CURL_CA_BUNDLE"
    else
      echo "${p}"
      return 0
    fi
  fi
  return 1
}

_ayil_wget_bin() {
  local c p
  for c in /usr/bin/wget; do
    if [[ -x "${c}" ]]; then
      echo "${c}"
      return 0
    fi
  done
  p="$(command -v wget 2>/dev/null || true)"
  if [[ -n "${p}" ]]; then
    echo "${p}"
    return 0
  fi
  return 1
}

_ayil_download_url() {
  local dest="$1"
  local url="$2"
  mkdir -p "$(dirname "${dest}")"

  local curl_bin wget_bin
  if curl_bin="$(_ayil_curl_bin)"; then
    _ayil_setup_curl_ca_bundle || true
    _ayil_log "Download via curl: ${curl_bin}"
    if "${curl_bin}" -fL --retry 3 --retry-delay 5 -C - -o "${dest}" "${url}"; then
      return 0
    fi
    _ayil_log "curl failed; trying wget if available"
  fi

  if wget_bin="$(_ayil_wget_bin)"; then
    _ayil_log "Download via wget: ${wget_bin}"
    if "${wget_bin}" -c -O "${dest}" "${url}"; then
      return 0
    fi
  fi

  echo "ERROR: Zenodo download failed (often SSL CA with conda base curl on HPC)." >&2
  echo "  Try: export CURL_CA_BUNDLE=/etc/pki/tls/certs/ca-bundle.crt" >&2
  echo "  Or:  conda deactivate && ./scripts/fetch_zenodo_inputs.sh" >&2
  echo "  Or:  module load curl  (if your site provides it)" >&2
  return 1
}

# Download zip (cached) and extract into AYiL_INPUTS.
ayil_ensure_zenodo_bundle() {
  if ayil_zenodo_bundle_ready; then
    return 0
  fi
  if [[ "${AYiL_SKIP_ZENODO_FETCH:-0}" == "1" ]]; then
    echo "ERROR: Zenodo inputs missing under ${AYiL_INPUTS} and AYiL_SKIP_ZENODO_FETCH=1" >&2
    echo "  Unzip ${AYiL_ZENODO_INPUT_ZIP} into ${AYiL_INPUTS} or unset AYiL_SKIP_ZENODO_FETCH." >&2
    return 1
  fi

  local zip_path="${AYiL_ZENODO_CACHE}/${AYiL_ZENODO_INPUT_ZIP}"
  mkdir -p "${AYiL_ZENODO_CACHE}" "${AYiL_INPUTS}"

  if [[ ! -f "${zip_path}" ]]; then
    _ayil_log "Downloading ${AYiL_ZENODO_INPUT_ZIP} from Zenodo record ${AYiL_ZENODO_RECORD} ..."
    _ayil_log "URL: ${AYiL_ZENODO_URL}"
    _ayil_log "Cache: ${zip_path}"
    _ayil_download_url "${zip_path}" "${AYiL_ZENODO_URL}"
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
    echo "ERROR: could not find day folders inside ${AYiL_ZENODO_INPUT_ZIP}" >&2
    find "${tmp}" -maxdepth 2 -type d | head -20 >&2 || true
    rm -rf "${tmp}"
    return 1
  fi

  _ayil_log "Installing inputs from ${src} -> ${AYiL_INPUTS}"
  _ayil_log "rsync --ignore-existing (keeps tracked/edited namoptions and other present files)"
  rsync -a --ignore-existing "${src}/" "${AYiL_INPUTS}/"
  rm -rf "${tmp}"

  {
    echo "record=${AYiL_ZENODO_RECORD}"
    echo "zip=${AYiL_ZENODO_INPUT_ZIP}"
    echo "url=${AYiL_ZENODO_URL}"
    echo "rsync=ignore-existing"
    echo "installed_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } > "${AYiL_ZENODO_MARKER}"

  if ! ayil_zenodo_bundle_ready; then
    echo "ERROR: extract finished but sample day ${AYiL_INPUTS}/20200720 is incomplete" >&2
    return 1
  fi
  _ayil_log "Zenodo inputs ready under ${AYiL_INPUTS}"
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
  echo "ERROR: no inputs for ${date} under ${AYiL_INPUTS} after Zenodo install" >&2
  return 1
}
