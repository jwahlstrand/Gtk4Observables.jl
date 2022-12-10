# Reference

## Input widgets

```@docs
button
checkbox
togglebutton
slider
textbox
textarea
dropdown
player
```

## Output widgets

```@docs
label
```

## Graphics

```@docs
canvas
Gtk4Observables.Canvas
Gtk4Observables.MouseHandler
DeviceUnit
UserUnit
Gtk4Observables.XY
Gtk4Observables.MouseButton
Gtk4Observables.MouseScroll
```

## Pan/zoom

```@docs
ZoomRegion
```

Note that if you create a `zrsig::Observable{ZoomRegion}`, then
```julia
push!(zrsig, XY(1..3, 1..5))
push!(zrsig, (1..5, 1..3))
push!(zrsig, (1:5, 1:3))
```
would all update the value of the `currentview` field to the same
value (`x = 1..3` and `y = 1..5`).


```@docs
pan_x
pan_y
zoom
init_zoom_rubberband
init_zoom_scroll
init_pan_drag
init_pan_scroll
```

## API
```@docs
observable
frame
Gtk4Observables.gc_preserve
```
