```@meta
CurrentModule = MOSAiCAYiL
```

# The vertical grid

Every AYiL day ran on the same 287 faces: uniform 10 m to 1220 m, a geometric stretch, then
uniform ≈185 m above 7139 m, to a top face at 11949.301 m.

![The DALES vertical grid](assets/vertical_grid.png)

```@example grid
using MOSAiCAYiL: MOSAiCAYiL as MA

length(MA.LES_FACES), MA.LES_FACES[1:3], MA.LES_TOP_FACE
```

[`MOSAiCAYiL.LES_FACES`](@ref) is written out as the file's own `Float32` values, so it
reproduces the grid exactly. [`MOSAiCAYiL.stretch_faces`](@ref) is the paper's Appendix A
formula and lands close but not bit-identical in the stretch:

```@example grid
formula = MA.stretch_faces(Float32)
maximum(abs, formula .- MA.LES_FACES)
```

Use `LES_FACES` for anything compared against the archive.

The horizontal grid is 6.4 km at 20 m, 320 × 320:

```@example grid
MA.PRODUCTION_GRID
```

## Cutting and thinning

A column for a model is built by composing two functions on the face vector:

```@example grid
faces = MA.truncate_faces_to_top(MA.LES_FACES, 2500)
length(faces), last(faces)
```

```@example grid
coarse = MA.coarsen_faces_to_dz_min(MA.LES_FACES, 50)
length(coarse), minimum(diff(coarse))
```

They compose, and the faces are the whole specification — there is no parallel `z_top` or
`dz_min` keyword elsewhere:

```@example grid
short = MA.coarsen_faces_to_dz_min(MA.truncate_faces_to_top(MA.LES_FACES, 2500), 50)
length(short), first(short), last(short)
```

[`MOSAiCAYiL.face_above_center`](@ref) snaps a height up to the face at or above it, which is
how the hand-checked domain tops were turned into face heights:

```@example grid
MA.face_above_center(2447.0)
```

## Metrics

[`MOSAiCAYiL.vertical_metrics`](@ref) builds the `dzf`/`dzh` arrays DALES's hydrostatic
integration steps through, from a full-level height array:

```@example grid
(; zf, dzf, dzh) = MA.vertical_metrics(collect(10.0:20.0:150.0))
dzf[1:4], dzh[1:4]
```

`vertical_metrics` returns `zh` alongside them — the cell faces, which DALES builds from the
centres by `zh[k+1] = zh[k] + 2(zf[k] − zh[k])`.

## Centres and faces are one grid

`prof.inp.001` column 1 is the vertical grid every run used: `modglobal.f90:411-433` reads it
as `zf` and builds every face from it. [`MOSAiCAYiL.LES_CENTRES`](@ref) is those 286 heights,
recovered from the stored faces as `(zh[k] + zh[k+1])/2` — the exact inverse of that
recursion, so it recurses back to [`MOSAiCAYiL.LES_FACES`](@ref) bit for bit:

```@example grid
Float32.(MA.vertical_metrics(MA.LES_CENTRES).zh) == MA.LES_FACES
```

The direction is worth keeping straight: in DALES the **centres** are primary and the faces
derived; in this package the faces are what is stored and the centres come back exactly.
