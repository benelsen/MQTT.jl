using Documenter, MQTT

makedocs(
    sitename="MQTT",
    format = Documenter.HTML(
        prettyurls = get(ENV, "CI", nothing) == "true"
    )
)

deploydocs(
    repo = "github.com/benelsen/MQTT.jl.git",
    devbranch = "julia1-support",
    devurl = "julia1-support",    
)
