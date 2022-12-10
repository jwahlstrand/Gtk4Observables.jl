using Documenter, Gtk4Observables, TestImages
testimage("lighthouse")    # ensure all artifacts get downloaded before running tests

makedocs(sitename = "Gtk4Observables",
         format   = Documenter.HTML(prettyurls = get(ENV, "CI", nothing) == "true"),
         pages    = ["index.md", "controls.md", "drawing.md", "zoom_pan.md", "reference.md"]
         )

deploydocs(repo         = "github.com/jwahlstrand/Gtk4Observables.jl.git",
           push_preview = true,
           )
