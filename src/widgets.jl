### Input widgets

"""
    init_wobsval([T], observable, value; default=nothing) -> observable, value
Return a suitable initial state for `observable` and `value` for a
widget. Any but one of these argument can be `nothing`. A new `observable`
will be created if the input `observable` is `nothing`. Passing in a
pre-existing `observable` will return the same observable, either setting the
observable to `value` (if specified as an input) or extracting and
returning its current value (if the `value` input is `nothing`).
Optionally specify the element type `T`; if `observable` is a
`Observables.Observable`, then `T` must agree with `eltype(observable)`.
"""
init_wobsval(::Nothing, ::Nothing; default=nothing) = _init_wobsval(nothing, default)
init_wobsval(::Nothing, value; default=nothing) = _init_wobsval(typeof(value), nothing, value)
init_wobsval(observable, value; default=nothing) = _init_wobsval(eltype(observable), observable, value)
init_wobsval(::Type{T}, ::Nothing, ::Nothing; default=nothing) where {T} =
    _init_wobsval(T, nothing, default)
init_wobsval(::Type{T}, observable, value; default=nothing) where {T} =
    _init_wobsval(T, observable, value)

_init_wobsval(::Nothing, value) = _init_wobsval(typeof(value), nothing, value)
_init_wobsval(::Type{T}, ::Nothing, value) where {T} = Observable{T}(value), value
_init_wobsval(::Type{T}, observable::Observable{T}, ::Nothing) where {T} =
    __init_wobsval(T, observable, observable[])
_init_wobsval(::Type{Union{Nothing, T}}, observable::Observable{T}, ::Nothing) where {T} =
    __init_wobsval(T, observable, observable[])
_init_wobsval(::Type{T}, observable::Observable{T}, value) where {T} = __init_wobsval(T, observable, value)
function __init_wobsval(::Type{T}, observable::Observable{T}, value) where T
    setindex!(observable, value)
    observable, value
end

"""
    init_observable2widget(widget::GtkWidget, id, observable) -> updatesignal
    init_observable2widget(getter, setter, widget::GtkWidget, id, observable) -> updatesignal
Update the "display" value of the Gtk widget `widget` whenever `observable`
changes. `id` is the observable handler id for updating `observable` from the
widget, and is required to prevent the widget from responding to the
update by firing `observable`.
If `updatesignal` is garbage-collected, the widget will no longer
update. Most likely you should either `preserve` or store
`updatesignal`.
"""
function init_observable2widget(getter::Function,
                                setter!::Function,
                                widget::GtkWidget,
                                id, observable)
    on(observable; weak=true) do val
        if signal_handler_is_connected(widget, id)
            signal_handler_block(widget, id)  # prevent "recursive firing" of the handler
            curval = getter(widget)
            try
                curval != val && setter!(widget, val)
            catch
                # if there's a problem setting the widget value, revert the observable
                observable[] = curval
                rethrow()
            end
            signal_handler_unblock(widget, id)
            nothing
        end
    end
end
init_observable2widget(widget::GtkWidget, id, observable) =
    init_observable2widget(defaultgetter, defaultsetter!, widget, id, observable)

defaultgetter(widget) = Gtk4.value(widget)
defaultsetter!(widget,val) = Gtk4.value(widget, val)

"""
    ondestroy(widget::GtkWidget, preserved)
Create a `destroy` callback for `widget` that terminates updating dependent signals.
"""
function ondestroy(widget::GtkWidget, preserved::AbstractVector)
    signal_connect(widget, "destroy") do widget
        empty!(preserved)
    end
    nothing
end

########################## Slider ############################

struct Slider{T<:Number} <: InputWidget{T}
    observable::Observable{T}
    widget::GtkScale
    id::Culong
    preserved::Vector{Any}

    function Slider{T}(observable::Observable{T}, widget, id, preserved) where T
        obj = new{T}(observable, widget, id, preserved)
        gc_preserve(widget, obj)
        obj
    end
end
Slider(observable::Observable{T}, widget::GtkScale, id, preserved) where {T} =
    Slider{T}(observable, widget, id, preserved)

medianidx(r) = (ax = axes(r)[1]; return (first(ax)+last(ax))??2)
# differs from median(r) in that it always returns an element of the range
medianelement(r::AbstractRange) = r[medianidx(r)]

slider(observable::Observable, widget::GtkScale, id, preserved = []) =
    Slider(observable, widget, id, preserved)

"""
    slider(range; widget=nothing, value=nothing, observable=nothing, orientation="horizontal")
Create a slider widget with the specified `range`. Optionally provide:
  - the GtkScale `widget` (by default, creates a new one)
  - the starting `value` (defaults to the median of `range`)
  - the (Observables.jl) `observable` coupled to this slider (by default, creates a new observable)
  - the `orientation` of the slider.
"""
function slider(range::AbstractRange{T};
                widget=nothing,
                value=nothing,
                observable=nothing,
                orientation="horizontal",
                syncsig=true,
                own=nothing) where T
    obsin = observable
    observable, value = init_wobsval(T, observable, value; default=medianelement(range))
    if own === nothing
        own = observable != obsin
    end
    if widget === nothing
        widget = GtkScale(:h,
                          first(range), last(range), step(range))
        Gtk4.G_.set_size_request(widget, 200, -1)
    else
        adj = Gtk4.GtkAdjustment(widget)
        Gtk4.configure!(adj; lower = first(range), upper = last(range), step_increment = step(range))
    end
    Gtk4.value(widget, value)

    ## widget -> observable
    id = signal_connect(widget, "value_changed") do w
        observable[] = round(T,defaultgetter(w))
    end

    ## observable -> widget
    preserved = []
    if syncsig
        push!(preserved, init_observable2widget(widget, id, observable))
    end
    if own
        ondestroy(widget, preserved)
    end

    Slider(observable, widget, id, preserved)
end

# Adjust the range on a slider
# Is calling this `setindex!` too much of a pun?
function Base.setindex!(s::Slider, (range,value)::Tuple{AbstractRange, Any})
    first(range) <= value <= last(range) || error("$value is not within the span of $range")
    adj = Gtk4.GtkAdjustment(widget(s))
    Gtk4.configure!(adj; value = value, lower = first(range), upper = last(range), step_increment = step(range))
end
Base.setindex!(s::Slider, range::AbstractRange) = setindex!(s, (range, s[]))

######################### Checkbox ###########################

struct Checkbox <: InputWidget{Bool}
    observable::Observable{Bool}
    widget::GtkCheckButton
    id::Culong
    preserved::Vector{Any}

    function Checkbox(observable::Observable{Bool}, widget, id, preserved)
        obj = new(observable, widget, id, preserved)
        gc_preserve(widget, obj)
        obj
    end
end

checkbox(observable::Observable, widget::GtkCheckButton, id, preserved=[]) =
    Checkbox(observable, widget, id, preserved)

"""
    checkbox(value=false; widget=nothing, observable=nothing, label="")
Provide a checkbox with the specified starting (boolean)
`value`. Optionally provide:
  - a GtkCheckButton `widget` (by default, creates a new one)
  - the (Observables.jl) `observable` coupled to this checkbox (by default, creates a new observable)
  - a display `label` for this widget
"""
function checkbox(value::Bool; widget=nothing, observable=nothing, label="", own=nothing)
    obsin = observable
    observable, value = init_wobsval(observable, value)
    if own === nothing
        own = observable != obsin
    end
    if widget === nothing
        widget = GtkCheckButton(label)
    end
    Gtk4.active(widget, value)

    id = signal_connect(widget, "toggled") do w
        observable[] = Gtk4.active(w)
    end
    preserved = []
    push!(preserved, init_observable2widget(w->Gtk4.active(w),
                                            (w,val)->Gtk4.active(w, val),
                                            widget, id, observable))
    if own
        ondestroy(widget, preserved)
    end

    Checkbox(observable, widget, id, preserved)
end
checkbox(; value=false, widget=nothing, observable=nothing, label="", own=nothing) =
    checkbox(value; widget=widget, observable=observable, label=label, own=own)

###################### ToggleButton ########################

struct ToggleButton <: InputWidget{Bool}
    observable::Observable{Bool}
    widget::GtkToggleButton
    id::Culong
    preserved::Vector{Any}

    function ToggleButton(observable::Observable{Bool}, widget, id, preserved)
        obj = new(observable, widget, id, preserved)
        gc_preserve(widget, obj)
        obj
    end
end

togglebutton(observable::Observable, widget::GtkToggleButton, id, preserved=[]) =
    ToggleButton(observable, widget, id, preserved)

"""
    togglebutton(value=false; widget=nothing, observable=nothing, label="")
Provide a togglebutton with the specified starting (boolean)
`value`. Optionally provide:
  - a GtkCheckButton `widget` (by default, creates a new one)
  - the (Observables.jl) `observable` coupled to this button (by default, creates a new observable)
  - a display `label` for this widget
"""
function togglebutton(value::Bool; widget=nothing, observable=nothing, label="", own=nothing)
    obsin = observable
    observable, value = init_wobsval(observable, value)
    if own === nothing
        own = observable != obsin
    end
    if widget === nothing
        widget = GtkToggleButton(label)
    end
    Gtk4.active(widget, value)

    id = signal_connect(widget, "toggled") do w
    setindex!(observable, Gtk4.active(w))
    end
    preserved = []
    push!(preserved, init_observable2widget(w->Gtk4.active(w),
                                        (w,val)->Gtk4.active(w, val),
                                        widget, id, observable))
    if own
        ondestroy(widget, preserved)
    end

    ToggleButton(observable, widget, id, preserved)
end
togglebutton(; value=false, widget=nothing, observable=nothing, label="", own=nothing) =
    togglebutton(value; widget=widget, observable=observable, label=label, own=own)

######################### Button ###########################

struct Button <: InputWidget{Nothing}
    observable::Observable{Nothing}
    widget::GtkButton
    id::Culong

    function Button(observable::Observable{Nothing}, widget, id)
        obj = new(observable, widget, id)
        gc_preserve(widget, obj)
        obj
    end
end

button(observable::Observable, widget::GtkButton, id) =
    Button(observable, widget, id)

"""
button(label; widget=nothing, observable=nothing)
button(; label=nothing, widget=nothing, observable=nothing)
Create a push button with text-label `label`. Optionally provide:
- a GtkButton `widget` (by default, creates a new one)
- the (Observables.jl) `observable` coupled to this button (by default, creates a new observable)
"""
function button(;
    label::Union{Nothing,String,Symbol}=nothing,
    widget=nothing,
    observable=nothing,
    own=nothing)
    obsin = observable
    if observable === nothing
        observable = Observable(nothing)
    end
    if own === nothing
        own = observable != obsin
    end
    if widget === nothing
        widget = GtkButton(label)
    end

    id = signal_connect(widget, "clicked") do w
        setindex!(observable, nothing)
    end

    Button(observable, widget, id)
end
button(label::Union{String,Symbol}; widget=nothing, observable=nothing, own=nothing) =
    button(; label=label, widget=widget, observable=observable, own=own)

######################### ColorButton ###########################

struct ColorButton{C} <: InputWidget{Nothing}
    observable::Observable{C}
    widget::GtkColorButton
    id::Culong
    preserved::Vector{Any}

    function ColorButton{C}(observable::Observable{C}, widget, id, preserved) where {T, C <: Color{T, 3}}
        obj = new(observable, widget, id, preserved)
        gc_preserve(widget, obj)
        obj
    end
end

colorbutton(observable::Observable{C}, widget::GtkColorButton, id, preserved = []) where {T, C <: Color{T, 3}} =
ColorButton{C}(observable, widget, id, preserved)

Base.convert(::Type{RGBA}, gcolor::Gtk4.GdkRGBA) = RGBA(gcolor.r, gcolor.g, gcolor.b, gcolor.a)
Base.convert(::Type{Gtk4.GdkRGBA}, color::Colorant) = Gtk4.GdkRGBA(red(color), green(color), blue(color), alpha(color))

"""
colorbutton(color; widget=nothing, observable=nothing)
colorbutton(; color=nothing, widget=nothing, observable=nothing)
Create a push button with color `color`. Clicking opens the Gtk color picker. Optionally provide:
- a GtkColorButton `widget` (by default, creates a new one)
- the (Observables.jl) `observable` coupled to this button (by default, creates a new observable)
"""
function colorbutton(;
    color::C = RGB(0, 0, 0),
    widget=nothing,
    observable=nothing,
    own=nothing) where {T, C <: Color{T, 3}}
    obsin = observable
    observable, color = init_wobsval(observable, color)
    if own === nothing
        own = observable != obsin
    end
    getcolor(w) = get_gtk_property(w, :rgba, Gtk4.GdkRGBA)
    setcolor!(w, val) = set_gtk_property!(w, :rgba, convert(Gtk4.GdkRGBA, val))
    if widget === nothing
        widget = GtkColorButton(convert(Gtk4.GdkRGBA, color))
    else
        setcolor!(widget, color)
    end
    id = signal_connect(widget, "color-set") do w
        setindex!(observable, convert(C, convert(RGBA, getcolor(widget))))
    end
    preserved = []
    push!(preserved, init_observable2widget(getcolor, setcolor!, widget, id, observable))

    if own
        ondestroy(widget, preserved)
    end

    ColorButton{C}(observable, widget, id, preserved)
end
colorbutton(color::Color{T, 3}; widget=nothing, observable=nothing, own=nothing) where T =
    colorbutton(; color=color, widget=widget, observable=observable, own=own)

######################## Textbox ###########################

struct Textbox{T} <: InputWidget{T}
    observable::Observable{T}
    widget::GtkEntry
    id::Culong
    preserved::Vector{Any}
    range

    function Textbox{T}(observable::Observable{T}, widget, id, preserved, range) where T
        obj = new{T}(observable, widget, id, preserved, range)
        gc_preserve(widget, obj)
        obj
    end
end
Textbox(observable::Observable{T}, widget::GtkEntry, id, preserved, range) where {T} =
    Textbox{T}(observable, widget, id, preserved, range)

textbox(observable::Observable, widget::GtkButton, id, preserved = []) =
    Textbox(observable, widget, id, preserved)

"""
    textbox(value=""; widget=nothing, observable=nothing, range=nothing, gtksignal=:activate)
    textbox(T::Type; widget=nothing, observable=nothing, range=nothing, gtksignal=:activate)
Create a box for entering text. `value` is the starting value; if you
don't want to provide an initial value, you can constrain the type
with `T`. Optionally specify the allowed range (e.g., `-10:10`)
for numeric entries, and/or provide the (Observables.jl) `observable` coupled
to this text box. Finally, you can specify which Gtk observable (e.g.
`activate`, `changed`) you'd like the widget to update with.
"""
function textbox(::Type{T};
                 widget=nothing,
                 value=nothing,
                 range=nothing,
                 observable=nothing,
                 syncsig=true,
                 own=nothing,
                 gtksignal::String="activate") where T
    if T <: AbstractString && range !== nothing
        throw(ArgumentError("You cannot set a range on a string textbox"))
    end
    if T <: Number && gtksignal == "changed"
        throw(ArgumentError("The `changed` signal with a numeric textbox is not supported."))
    end
    obsin = observable
    observable, value = init_wobsval(T, observable, value; default="")
    if own === nothing
        own = observable != obsin
    end
    if widget === nothing
        widget = GtkEntry()
    end
    set_gtk_property!(widget, "text", value)

    id = signal_connect(widget, gtksignal) do w, _...
        setindex!(observable, entrygetter(w, observable, range))
        return false
    end

    preserved = []
    function checked_entrysetter!(w, val)
        val ??? range || throw(ArgumentError("$val is not within $range"))
        entrysetter!(w, val)
    end
    if syncsig
        push!(preserved, init_observable2widget(w->entrygetter(w, observable, range),
                                                range === nothing ? entrysetter! : checked_entrysetter!,
                                                widget, id, observable))
    end
    own && ondestroy(widget, preserved)

    Textbox(observable, widget, id, preserved, range)
end
function textbox(value::T;
                 widget=nothing,
                 range=nothing,
                 observable=nothing,
                 syncsig=true,
                 own=nothing,
                 gtksignal="activate") where T
    textbox(T; widget=widget, value=value, range=range, observable=observable, syncsig=syncsig, own=own, gtksignal=gtksignal)
end

entrygetter(w, ::Observable{<:AbstractString}, ::Nothing) =
    get_gtk_property(w, "text", String)
function entrygetter(w, observable::Observable{T}, range) where T
    val = tryparse(T, get_gtk_property(w, "text", String))
    if val === nothing
        nval = observable[]
        # Invalid entry, restore the old value
        entrysetter!(w, nval)
    else
        nval = nearest(val, range)
        if val != nval
            entrysetter!(w, nval)
        end
    end
    nval
end
nearest(val, ::Nothing) = val
function nearest(val, r::AbstractRange)
    i = round(Int, (val - first(r))/step(r)) + 1
    ax = axes(r)[1]
    r[clamp(i, first(ax), last(ax))]
end

entrysetter!(w, val) = set_gtk_property!(w, "text", string(val))

######################### Textarea ###########################

struct Textarea <: InputWidget{String}
    observable::Observable{String}
    widget::GtkTextView
    id::Culong
    preserved::Vector{Any}

    function Textarea(observable::Observable{String}, widget, id, preserved)
        obj = new(observable, widget, id, preserved)
        gc_preserve(widget, obj)
        obj
    end
end

"""
    textarea(value=""; widget=nothing, observable=nothing)
Creates an extended text-entry area. Optionally provide a GtkTextView `widget`
and/or the (Observables.jl) `observable` associated with this widget. The
`observable` updates when you type.
"""
function textarea(value::String="";
                  widget=nothing,
                  observable=nothing,
                  syncsig=true,
                  own=nothing)
    obsin = observable
    observable, value = init_wobsval(observable, value)
    if own === nothing
        own = observable != obsin
    end
    if widget === nothing
        widget = GtkTextView()
    end
    buf = widget[:buffer, GtkTextBuffer]
    buf[String] = value
    sleep(0.01)   # without this, we more frequently get segfaults...not sure why

    id = signal_connect(buf, "changed") do w
        setindex!(observable, w[String])
    end

    preserved = []
    if syncsig
        # GtkTextBuffer is not a GtkWidget, so we have to do this manually
        push!(preserved, on(observable; weak=true) do val
                  signal_handler_block(buf, id)
                  curval = get_gtk_property(buf, "text", String)
                  curval != val && set_gtk_property!(buf, "text", val)
                  signal_handler_unblock(buf, id)
                  nothing
              end)
    end
    own && ondestroy(widget, preserved)

    Textarea(observable, widget, id, preserved)
end

##################### SelectionWidgets ######################

struct Dropdown <: InputWidget{String}
    observable::Union{Observable{String}, Observable{Union{Nothing, String}}} # consider removing support for Observable{String} in next breaking release
    mappedsignal::Observable{Any}
    widget::GtkComboBoxText
    str2int::Dict{String,Int}
    id::Culong
    preserved::Vector{Any}

    function Dropdown(observable::Union{Observable{String}, Observable{Union{Nothing, String}}}, mappedsignal::Observable, widget, str2int, id, preserved)
        obj = new(observable, mappedsignal, widget, str2int, id, preserved)
        gc_preserve(widget, obj)
        obj
    end
end

"""
    dropdown(choices; widget=nothing, value=first(choices), observable=nothing, label="", with_entry=true, icons, tooltips)
Create a "dropdown" widget. `choices` can be a vector (or other iterable) of
options. These options might either be a list of strings, or a list of `choice::String => func` pairs
so that an action encoded by `func` can be taken when `choice` is selected.
Optionally specify
  - the GtkComboBoxText `widget` (by default, creates a new one)
  - the starting `value`
  - the (Observables.jl) `observable` coupled to this slider (by default, creates a new observable)
  - whether the widget should allow text entry
# Examples
    dd = dropdown(["one", "two", "three"])
To link a callback to the dropdown, use
    dd = dropdown(("turn red"=>colorize_red, "turn green"=>colorize_green))
    on(dd.mappedsignal) do cb
        cb(img)                     # img is external data you want to act on
    end
`cb` does not fire for the initial value of `dd`; if this is desired, manually execute
`dd[] = dd[]` after defining this action.
`dd.mappedsignal` is a function-observable only for the pairs syntax for `choices`.
"""
function dropdown(; choices=nothing,
                  widget=nothing,
                  value=nothing,
                  observable=nothing,
                  label="",
                  with_entry=true,
                  icons=nothing,
                  tooltips=nothing,
                  own=nothing)
    obsin = observable
    observable, value = init_wobsval(Union{Nothing, String}, observable, value)
    if own === nothing
        own = observable != obsin
    end
    if widget === nothing
        widget = GtkComboBoxText()
    end
    if choices !== nothing
        empty!(widget)
    else
        error("Pre-loading the widget is not yet supported")
    end
    allstrings = all(x->isa(x, AbstractString), choices)
    allstrings || all(x->isa(x, Pair), choices) || throw(ArgumentError("all elements must either be strings or pairs, got $choices"))
    str2int = Dict{String,Int}()
    getactive(w) = Gtk4.active_text(w)
    setactive!(w, val) = (i = val !== nothing ? str2int[val] : -1; set_gtk_property!(w, :active, i))
    if length(choices) > 0
        if value === nothing || (observable isa Observable{String} && value ??? juststring.(choices))
            # default to the first choice if value is nothing, or else if it's an empty String observable
            # and none of the choices are empty strings
            value = juststring(first(choices))
            observable[] = value
        end
    end
    k = -1
    for c in choices
        str = juststring(c)
        push!(widget, str)
        str2int[str] = (k+=1)
    end
    setactive!(widget, value)

    id = signal_connect(widget, "changed") do w
        setindex!(observable, getactive(w))
    end

    preserved = []
    push!(preserved, init_observable2widget(getactive, setactive!, widget, id, observable))
    mappedsignal = Observable{Any}(nothing)
    if !allstrings
        choicedict = Dict(choices...)
        map!(mappedsignal, observable) do val
            if val !== nothing
                choicedict[val]
            else
                _ -> nothing
            end
        end
    end
    if own
        ondestroy(widget, preserved)
    end

    Dropdown(observable, mappedsignal, widget, str2int, id, preserved)
end

function Base.precompile(w::Dropdown)
    return invoke(precompile, Tuple{Widget}, w) & precompile(w.mappedsignal)
end

function dropdown(choices; kwargs...)
    dropdown(; choices=choices, kwargs...)
end

function Base.append!(w::Dropdown, choices)
    allstrings = all(x->isa(x, AbstractString), choices)
    allstrings || all(x->isa(x, Pair), choices) || throw(ArgumentError("all elements must either be strings or pairs, got $choices"))
    allstrings && w.mappedsignal[] === nothing || throw(ArgumentError("only pairs may be added to a combobox with pairs, got $choices"))
    k = length(w.str2int) - 1
    for c in choices
        str = juststring(c)
        push!(w.widget, str)
        w.str2int[str] = (k+=1)
    end
    return w
end

function Base.empty!(w::Dropdown)
    w.observable isa Observable{String} &&
        throw(ArgumentError("empty! is only supported when the associated observable is of type $(Union{Nothing, String})"))
    empty!(w.str2int)
    empty!(w.widget)
    w.mappedsignal[] = nothing
    return w
end

juststring(str::AbstractString) = String(str)
juststring(p::Pair{String}) = p.first
pairaction(str::AbstractString) = x->nothing
pairaction(p::Pair{String,F}) where {F<:Function} = p.second

### Output Widgets

######################## Label #############################

struct Label <: Widget
    observable::Observable{String}
    widget::GtkLabel
    preserved::Vector{Any}

    function Label(observable::Observable{String}, widget, preserved)
        obj = new(observable, widget, preserved)
        gc_preserve(widget, obj)
        obj
    end
end

"""
    label(value; widget=nothing, observable=nothing)
Create a text label displaying `value` as a string. Optionally specify
  - the GtkLabel `widget` (by default, creates a new one)
  - the (Observables.jl) `observable` coupled to this label (by default, creates a new observable)
"""
function label(value;
               widget=nothing,
               observable=nothing,
               syncsig=true,
               own=nothing)
    obsin = observable
    observable, value = init_wobsval(String, observable, value)
    if own === nothing
        own = observable != obsin
    end
    if widget === nothing
        widget = GtkLabel(value)
    else
        set_gtk_property!(widget, "label", value)
    end
    preserved = []
    if syncsig
        let widget=widget
            push!(preserved, on(observable; weak=true) do val
                set_gtk_property!(widget, "label", val)
            end)
        end
    end
    if own
        ondestroy(widget, preserved)
    end
    Label(observable, widget, preserved)
end

########################## SpinButton ########################

struct SpinButton{T<:Number} <: InputWidget{T}
    observable::Observable{T}
    widget::GtkSpinButton
    id::Culong
    preserved::Vector{Any}

    function SpinButton{T}(observable::Observable{T}, widget, id, preserved) where T
        obj = new{T}(observable, widget, id, preserved)
        gc_preserve(widget, obj)
        obj
    end
end
SpinButton(observable::Observable{T}, widget::GtkSpinButton, id, preserved) where {T} =
    SpinButton{T}(observable, widget, id, preserved)

spinbutton(observable::Observable, widget::GtkSpinButton, id, preserved = []) =
    SpinButton(observable, widget, id, preserved)

"""
    spinbutton(range; widget=nothing, value=nothing, observable=nothing, orientation="horizontal")
Create a spinbutton widget with the specified `range`. Optionally provide:
  - the GtkSpinButton `widget` (by default, creates a new one)
  - the starting `value` (defaults to the start of `range`)
  - the (Observables.jl) `observable` coupled to this spinbutton (by default, creates a new observable)
  - the `orientation` of the spinbutton.
"""
function spinbutton(range::AbstractRange{T};
                    widget=nothing,
                    value=nothing,
                    observable=nothing,
                    orientation="horizontal",
                    syncsig=true,
                    own=nothing) where T
    obsin = observable
    observable, value = init_wobsval(T, observable, value; default=range.start)
    if own === nothing
        own = observable != obsin
    end
    if widget === nothing
        widget = GtkSpinButton(
                          first(range), last(range), step(range))
        Gtk4.G_.set_size_request(widget, 200, -1)
    else
        adj = Gtk4.GtkAdjustment(widget)
        Gtk4.configure!(adj; lower=first(range), upper=last(range), step_increment=step(range))
    end
    if lowercase(first(orientation)) == 'v'
        Gtk4.orientation(Gtk4.GtkOrientable(widget),
                           Gtk4.Orientation_VERTICAL)
    end
    Gtk4.value(widget, value)

    ## widget -> observable
    id = signal_connect(widget, "value_changed") do w
        setindex!(observable, defaultgetter(w))
    end

    ## observable -> widget
    preserved = []
    if syncsig
        push!(preserved, init_observable2widget(widget, id, observable))
    end
    if own
        ondestroy(widget, preserved)
    end

    SpinButton(observable, widget, id, preserved)
end

# Adjust the range on a spinbutton
# Is calling this `setindex!` too much of a pun?
function Base.setindex!(s::SpinButton, (range,value)::Tuple{AbstractRange,Any})
    first(range) <= value <= last(range) || error("$value is not within the span of $range")
    adj = Gtk4.GtkAdjustment(widget(s))
    Gtk4.configure!(adj; value = value, lower = first(range), upper = last(range), step_increment = step(range))
end
Base.setindex!(s::SpinButton, range::AbstractRange) = setindex!(s, (range, s[]))

########################## CyclicSpinButton ########################

struct CyclicSpinButton{T<:Number} <: InputWidget{T}
    observable::Observable{T}
    widget::GtkSpinButton
    id::Culong
    preserved::Vector{Any}

    function CyclicSpinButton{T}(observable::Observable{T}, widget, id, preserved) where T
        obj = new{T}(observable, widget, id, preserved)
        gc_preserve(widget, obj)
        obj
    end
end
CyclicSpinButton(observable::Observable{T}, widget::GtkSpinButton, id, preserved) where {T} =
    CyclicSpinButton{T}(observable, widget, id, preserved)

cyclicspinbutton(observable::Observable, widget::GtkSpinButton, id, preserved = []) =
    CyclicSpinButton(observable, widget, id, preserved)

"""
    cyclicspinbutton(range, carry_up; widget=nothing, value=nothing, observable=nothing, orientation="horizontal")
Create a cyclicspinbutton widget with the specified `range` that updates a `carry_up::Observable{Bool}`
only when a value outside the `range` of the cyclicspinbutton is pushed. `carry_up`
is updated with `true` when the cyclicspinbutton is updated with a value that is
higher than the maximum of the range. When cyclicspinbutton is updated with a value that is smaller
than the minimum of the range `carry_up` is updated with `false`. Optional arguments are:
  - the GtkSpinButton `widget` (by default, creates a new one)
  - the starting `value` (defaults to the start of `range`)
  - the (Observables.jl) `observable` coupled to this cyclicspinbutton (by default, creates a new observable)
  - the `orientation` of the cyclicspinbutton.
"""
function cyclicspinbutton(range::AbstractRange{T}, carry_up::Observable{Bool};
                          widget=nothing,
                          value=nothing,
                          observable=nothing,
                          orientation="horizontal",
                          syncsig=true,
                          own=nothing) where T
    obsin = observable
    observable, value = init_wobsval(T, observable, value; default=range.start)
    if own === nothing
        own = observable != obsin
    end
    if widget === nothing
        widget = GtkSpinButton(first(range) - step(range), last(range) + step(range), step(range))
        Gtk4.G_.set_size_request(widget, 200, -1)
    else
        adj = Gtk4.GtkAdjustment(widget)
        Gtk4.configure!(adj; lower = first(range) - step(range), upper = last(range) + step(range), step_increment = step(range))
    end
    if lowercase(first(orientation)) == 'v'
        Gtk4.orientation(Gtk4.GtkOrientable(widget),
                           Gtk4.Orientation_VERTICAL)
    end
    Gtk4.value(widget, value)

    ## widget -> observable
    id = signal_connect(widget, "value_changed") do w
        setindex!(observable, defaultgetter(w))
    end

    ## observable -> widget
    preserved = []
    if syncsig
        push!(preserved, init_observable2widget(widget, id, observable))
    end
    if own
        ondestroy(widget, preserved)
    end

    push!(preserved, on(observable; weak=true) do val
        if val > maximum(range)
            observable.val = minimum(range)
            setindex!(carry_up, true)
        end
    end)
    push!(preserved, on(observable; weak=true) do val
        if val < minimum(range)
            observable.val = maximum(range)
            setindex!(carry_up, false)
        end
    end)
    setindex!(observable, value)

    CyclicSpinButton(observable, widget, id, preserved)
end

######################## ProgressBar #########################

struct ProgressBar{T <: Number} <: Widget
    observable::Observable{T}
    widget::GtkProgressBar
    preserved::Vector{Any}

    function ProgressBar{T}(observable::Observable{T}, widget, preserved) where T
        obj = new{T}(observable, widget, preserved)
        gc_preserve(widget, obj)
        obj
    end
end
ProgressBar(observable::Observable{T}, widget::GtkProgressBar, preserved) where {T} =
    ProgressBar{T}(observable, widget, preserved)

# convert a member of the interval into a decimal
interval2fraction(x::AbstractInterval, i) = (i - minimum(x))/IntervalSets.width(x)

"""
    progressbar(interval::AbstractInterval; widget=nothing, observable=nothing)
Create a progressbar displaying the current state in the given interval. Optionally specify
  - the GtkProgressBar `widget` (by default, creates a new one)
  - the (Observables.jl) `observable` coupled to this progressbar (by default, creates a new observable)
# Examples
```julia-repl
julia> using Gtk4Observables
julia> using IntervalSets
julia> n = 10
julia> pb = progressbar(1..n)
Gtk.GtkProgressBarLeaf with 1: "input" = 1 Int64
julia> for i = 1:n
           # do something
           pb[] = i
       end
```
"""
function progressbar(interval::AbstractInterval{T};
                     widget=nothing,
                     observable=nothing,
                     syncsig=true,
                     own=nothing) where T<:Number
    value = minimum(interval)
    obsin = observable
    observable, value = init_wobsval(T, observable, value)
    if own === nothing
        own = observable != obsin
    end
    if widget === nothing
        widget = GtkProgressBar()
    else
        set_gtk_property!(widget, "fraction", interval2fraction(interval, value))
    end
    preserved = []
    if syncsig
        push!(preserved, on(observable; weak=true) do val
            set_gtk_property!(widget, "fraction", interval2fraction(interval, val))
        end)
    end
    if own
        ondestroy(widget, preserved)
    end
    ProgressBar(observable, widget, preserved)
end

progressbar(range::AbstractRange; args...) = progressbar(ClosedInterval(range); args...)
