"""
    paths.jl

Access to the MOSAiC AYiL day directories from the lazy Zenodo artifact, or from
an explicit `root` keyword.
"""

const ARTIFACT_NAME = "ayil_config_input_results"

package_root() = dirname(@__DIR__)

function _artifacts_toml(; package = package_root())
    return joinpath(package, "Artifacts.toml")
end

"""
    artifact_installed()

Whether the lazy `$ARTIFACT_NAME` artifact is already on disk. Does not download.
"""
function artifact_installed()
    hash = _artifact_hash()
    return hash !== nothing && Artifacts.artifact_exists(hash)
end

_has_scm_in(root) =
    isfile(joinpath(root, "20200503", "scm_in.a_year_in_les.20200503.nc"))

function _artifact_hash()
    return Artifacts.artifact_hash(ARTIFACT_NAME, _artifacts_toml())
end

"""
    artifact_root()

The lazy `$ARTIFACT_NAME` directory (Zenodo 10.5281/zenodo.10491362, ~911 MB).
Downloads on first use, not at package load.
"""
function artifact_root()
    hash = _artifact_hash()
    isnothing(hash) && error(
        "The `$ARTIFACT_NAME` artifact is not bound in $(_artifacts_toml()). \
         Run `gen/build_data_artifact.jl`.",
    )
    LazyArtifacts.ensure_artifact_installed(ARTIFACT_NAME, _artifacts_toml())
    return Artifacts.artifact_path(hash)
end

"""
    data_root(; root = artifact_root())

Directory holding one subdirectory per AYiL day. Default is [`artifact_root`](@ref).
Pass `root` for a local tree. Does not download at package load.
"""
function data_root(; root = artifact_root())
    isdir(root) || error("`root` is not a directory: $root")
    return root
end

"""
    data_available()
    data_available(root)

Whether the default artifact (already on disk) or `root` can serve day files.
Does not download.
"""
data_available() =
    artifact_installed() && _has_scm_in(Artifacts.artifact_path(_artifact_hash()))
data_available(root::AbstractString) = isdir(root) && _has_scm_in(root)

"""Published AYiL dates whose day directory exists under `root`."""
function available_dates(; root = data_root())
    return filter(d -> isdir(day_dir(d; root)), collect(MOSAiCAYiL_dates))
end


"""
    day_dir(date; root = data_root())

The directory of one AYiL day, given `date` as `yyyymmdd`, a `Date`, or a case.
"""
function day_dir(date::AbstractString; root = data_root())
    return joinpath(root, date)
end

day_dir(date::Dates.Date; kwargs...) = day_dir(date_string(date); kwargs...)
day_dir(c::MOSAiCAYiLCase; kwargs...) = day_dir(c.date; kwargs...)

scm_in_path(date; kwargs...) =
    joinpath(day_dir(date; kwargs...), "scm_in.a_year_in_les.$(date_string(date)).nc")

les_profiles_path(date; kwargs...) =
    joinpath(day_dir(date; kwargs...), "profiles.001.nc")

tmser_path(date; kwargs...) = joinpath(day_dir(date; kwargs...), "tmser.001.nc")

mphys_path(date; kwargs...) =
    joinpath(day_dir(date; kwargs...), "mphysprofiles.001.nc")

samptend_path(date; kwargs...) =
    joinpath(day_dir(date; kwargs...), "samptend.001.nc")

namoptions_path(date; kwargs...) = joinpath(day_dir(date; kwargs...), "namoptions")

# The other six files of a day directory. DALES's plain-text inputs and its text copies of
# `tmser`. `prof.inp.001` column 1 is the vertical grid every run used
# (`modglobal.f90:411-419`); only its five profile columns are unused, `ltestbed` taking the
# `scm_in` branch.

prof_inp_path(date; kwargs...) = joinpath(day_dir(date; kwargs...), "prof.inp.001")

baseprof_inp_path(date; kwargs...) =
    joinpath(day_dir(date; kwargs...), "baseprof.inp.001")

ckd_inp_path(date; kwargs...) = joinpath(day_dir(date; kwargs...), "ckd.inp.001")

cldwtr_inp_path(date; kwargs...) = joinpath(day_dir(date; kwargs...), "cldwtr.inp.001")

tmser1_path(date; kwargs...) = joinpath(day_dir(date; kwargs...), "tmser1.001")

tmsurf_path(date; kwargs...) = joinpath(day_dir(date; kwargs...), "tmsurf.001")

"""
    day_files(date; root = data_root())

Every file of one AYiL day, as `name => path`, whether or not it exists on disk.
"""
day_files(date; kwargs...) = (;
    scm_in = scm_in_path(date; kwargs...),
    profiles = les_profiles_path(date; kwargs...),
    tmser = tmser_path(date; kwargs...),
    mphys = mphys_path(date; kwargs...),
    samptend = samptend_path(date; kwargs...),
    namoptions = namoptions_path(date; kwargs...),
    prof_inp = prof_inp_path(date; kwargs...),
    baseprof_inp = baseprof_inp_path(date; kwargs...),
    ckd_inp = ckd_inp_path(date; kwargs...),
    cldwtr_inp = cldwtr_inp_path(date; kwargs...),
    tmser1 = tmser1_path(date; kwargs...),
    tmsurf = tmsurf_path(date; kwargs...),
)
