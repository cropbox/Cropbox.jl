using Cropbox
using CSV
using DataFrames: DataFrames, DataFrame
using DataStructures: OrderedDict
using GenieFramework
using Genie, Genie.Renderer, Genie.Renderer.Json, Genie.Requests
using Dates
using TimeZones
import Genie.Renderer.Html

datetime_from_julian_day_WEA(year, jday, time::Time, tz::TimeZone, occurrence) =
zoned_datetime(Date(year) + (Day(jday) - Day(1)) + time, tz, occurrence)
datetime_from_julian_day_WEA(year, jday, tz::TimeZone) = datetime_from_julian_day_WEA(year, jday, "00:00", tz)

#HACK: handle different API for Fixed/VariableTimeZone
zoned_datetime(dt::DateTime, tz::TimeZone, occurrence=1) = ZonedDateTime(dt, tz)
zoned_datetime(dt::DateTime, tz::VariableTimeZone, occurrence=1) = ZonedDateTime(dt, tz, occurrence)

# Handle .wea files
loadwea(filename, timezone; indexkey=:index) = begin
    df = CSV.File(filename) |> DataFrame
    df[!, indexkey] = map(r -> begin
        occurrence = 1
        i = DataFrames.row(r)
        if i > 1
            r0 = parent(r)[i-1, :]
            r0.time == r.time && (occurrence = 2)
        end
        datetime_from_julian_day_WEA(r.year, r.jday, r.time, timezone, occurrence)
    end, eachrow(df))
    df
end

"""
Starts a web-based user interface for given Cropbox model.
"""
function launch_ui(S::Type{<:System})
    # At launch
    route("/") do
        model_name = String(nameof(S))                       # Model name for page header.
        config = parameters(S)                               # Retrieve default model configuration.
        variables = Cropbox.fieldunits(S) |> keys |> collect # Retrive all the variables within the model.
        D = Cropbox.dependency(S)
    
        # Get list of parameter names to search in dependency
        params = []
        for (_, dict) in config
            for (key, _) in dict
                push!(params, key)
            end
        end
    
        # Create OrderedDict of systems and parameters for form generation
        system_params = OrderedDict{String, OrderedDict{String, OrderedDict{Symbol, Any}}}()
        for param in params
            for node in D.N
                if param == node.info.name && !occursin("Vector", string(node.info.type)) && node.info.state != :Tabulate
                    system_name = String(node.info.system)
                    param_name = String(param)
    
                    if !haskey(system_params, system_name)
                        system_params[system_name] = OrderedDict{String, OrderedDict{Symbol, Any}}()
                    end
    
                    system_params[system_name][param_name] = OrderedDict(
                        :alias => node.info.alias,
                        :value => config[Symbol(model_name)][param] |> deunitfy,
                        :state => node.info.state,
                        :type => node.info.type,
                        :unit => Cropbox.fieldunit(S, param)
                    )
                end
            end
        end
    
        # Generate the HTML form dynamically based on parameters
        forms_html = ""
        for (system_name, params_dict) in system_params
            # forms_html *= "<h3>$system_name</h3>"
            forms_html *= """
            <div class="collapsible-container">
                <h3 class="collapsible-header" onclick="toggleVisibility(this)">$system_name</h3>
                <div class="collapsible-content">
            """
    
            for (param_name, param_info) in params_dict
                key = "$(system_name)__$(param_name)"
                unit = param_info[:unit] !== nothing ? " $(param_info[:unit])" : ""
    
                if param_info[:state] == :Provide
                    # File upload form
                    forms_html *= """
                    <div class='parameter-container'>
                        <label for='$key'>$param_name</label>
                        <input type='file' id='$key' name='$(key)__file'>
                        <span class='unit'>$unit</span>
                        <br>
                    </div>
                    """
                elseif param_info[:type] == :(Cropbox.typefor(Main.Cropbox.TimeZones.ZonedDateTime))
                    # Datetime form
                    forms_html *= """
                    <div class='parameter-container'>
                        <label>$param_name</label>
                        <div class='datetime-row'>
                            <input type='number' id='$(key)__year' name='$(key)__year' placeholder='Year' value='' class='datetime-input'>
                            <input type='number' id='$(key)__month' name='$(key)__month' placeholder='Month' value='' class='datetime-input'>
                            <input type='number' id='$(key)__day' name='$(key)__day' placeholder='Day' value='' class='datetime-input'>
                            <input type='text' id='$(key)__timezone' name='$(key)__timezone' placeholder='Timezone' value='' class='datetime-input'>
                            <span class='unit'>$unit</span>
                        </div>
                    </div>
                    """
                # elseif param_info[:type] |> eval |> supertype == Enum{Int32}
                #     # Enums? There's probably a better way for this...
                #     value = param_info[:value]
                #     forms_html *= """
                #     <div class='parameter-container'>
                #         <label for='$key'>$param_name</label>
                #         <input type='text' id='$(key)__enum' name='$(key)__enum' value='$value'>
                #         <span class='unit'>$unit</span>
                #         <br>
                #     </div>
                #     """
                # elseif param_info[:type] |> eval |> supertype != Enum{Int32}
                elseif !occursin("SoilClass", param_info[:type] |> string) && !occursin("LeafAngle", param_info[:type] |> string)
                    # Regular parameter form
                    value = param_info[:value]
                    forms_html *= """
                    <div class='parameter-container'>
                        <label for='$key'>$param_name</label>
                        <input type='text' id='$key' name='$key' value='$value'>
                        <span class='unit'>$unit</span>
                        <br>
                    </div>
                    """
                end
            end

            forms_html *= """
                </div> <!-- End of collapsible-content -->
            </div> <!-- End of collapsible-container -->
            """
        end

        # Separate form generation for potential variable names for the `target`` keyword
        target_html = """
        <div class='parameter-container'>
            <select id="Options__target_skip" name="Options__target_skip" class="dropdown">
                <option value="" disabled selected>Select parameters</option>
        """
        for var in variables
            target_html *= "<option value='$(string(var))'>$(string(var))</option>"
        end
        target_html *= "</select></div>"
    
        # Read the base HTML template and replace necessary forms
        html_page = read(joinpath(@__DIR__, "../../assets/ui.html"), String)
        html_page = replace(html_page, "{{model_name}}" => model_name)
        html_page = replace(html_page, "{{regular_params_form}}" => forms_html)
        html_page = replace(html_page, "{{target_dropdown}}" => target_html)
        
        return html(html_page)
    end

    # At simulation
    route("/simulate", method = POST) do
        # Model
        model_params = OrderedDict{Symbol, Any}()
        datetime_params = OrderedDict{Symbol, Any}()

        # Clock
        clock_params = OrderedDict{Symbol, Any}()

        # Calendar
        calendar_params = OrderedDict{Symbol, Any}()

        payload = jsonpayload()     # JSONPAYLOAD = JULIA DICT FORMAT
        step_unit = payload["Clock__unit_skip"]
    
        for (key, value) in payload
            if key == "selected_targets"
                continue
            end
            
            parts = split(key, "__")
            system_key = Symbol(parts[1])
            param_key = Symbol(parts[2])

            if occursin("_skip", key)
                continue
            end
        
            if system_key == :Clock
                # Handle Clock system parameters
                clock_params[:Clock] = OrderedDict{Symbol, Any}()

                if step_unit == "day"
                    clock_params[:Clock][param_key] = parse(Float64, string(value)) * u"d"
                else
                    clock_params[:Clock][param_key] = parse(Float64, string(value))
                end
        
            elseif system_key == :Calendar && length(parts) == 3 && parts[3] in ["year", "month", "day", "timezone"]
                # Handle Calendar system datetime parameters
                if !haskey(calendar_params, param_key)
                    calendar_params[param_key] = OrderedDict{String, Any}()
                end
                calendar_params[param_key][parts[3]] = value
        
            elseif length(parts) == 2
                # Handle regular parameters
                if !haskey(model_params, system_key)
                    model_params[system_key] = OrderedDict{Symbol, Any}()
                end
                try
                    model_params[system_key][param_key] = parse(Float64, string(value))
                catch e
                    model_params[system_key][param_key] = string(value)
                end
        
            elseif length(parts) == 3 && parts[3] in ["year", "month", "day", "timezone"]
                if !haskey(datetime_params, system_key)
                    datetime_params[system_key] = OrderedDict{Symbol, Dict{Symbol, Any}}()
                end
                if !haskey(datetime_params[system_key], param_key)
                    datetime_params[system_key][param_key] = OrderedDict{String, Any}()
                end
                datetime_params[system_key][param_key][parts[3]] = value

            # elseif parts[end] == "enum"
            #     if !haskey(model_params, system_key)
            #         model_params[system_key] = OrderedDict{Symbol, Any}()
            #     end
            #     model_params[system_key][param_key] = value |> Symbol |> eval
        
            elseif parts[end] == "file"
                # Handle file upload parameters
                if !haskey(model_params, system_key)
                    model_params[system_key] = OrderedDict{Symbol, Any}()
                end

                # println(value))

                if payload["$(key)_extension_skip"] == "wea"
                    # println("WEA file content:", value)
                    model_params[system_key][param_key] = loadwea(IOBuffer(value), tz"America/Los_Angeles")
                elseif payload["$(key)_extension_skip"] == "csv"
                    model_params[system_key][param_key] = CSV.read(IOBuffer(value), DataFrame)
                end
            end
        end

        calendar = OrderedDict{Symbol, Any}()
        calendar[:Calendar] = OrderedDict{Symbol, Any}()
        for (param_key, datetime_dict) in calendar_params
            year = parse(Int, datetime_dict["year"])
            month = parse(Int, datetime_dict["month"])
            day = parse(Int, datetime_dict["day"])
            timezone = datetime_dict["timezone"]
            datetime_value = ZonedDateTime(year, month, day, TimeZone(timezone))
            calendar[:Calendar][param_key] = datetime_value
        end

        for (system_key, params) in datetime_params
            for (param_key, datetime_dict) in params
                year = parse(Int, datetime_dict["year"])
                month = parse(Int, datetime_dict["month"])
                day = parse(Int, datetime_dict["day"])
                timezone = datetime_dict["timezone"]
                datetime_value = ZonedDateTime(year, month, day, TimeZone(timezone))
                model_params[system_key] = get(model_params, system_key, OrderedDict{Symbol, Any}())
                model_params[system_key][param_key] = datetime_value
            end
        end

        config = @config (model_params, clock_params, calendar)
    
        kwargs = Dict{Symbol, Any}()

        if haskey(payload, "Options__stop_number_skip")
            stop_value = parse(Float64, payload["Options__stop_number_skip"])
            if payload["Options__stop_unit_skip"] == "hour"
                kwargs[:stop] = stop_value * u"hr"
            elseif payload["Options__stop_unit_skip"] == "day"
                kwargs[:stop] = stop_value * u"d"
            elseif payload["Options__stop_unit_skip"] == "year"
                kwargs[:stop] = stop_value * u"yr"
            end
        end
        
        if haskey(payload, "Options__snap_number_skip")
            snap_value = parse(Float64, payload["Options__snap_number_skip"])
            if payload["Options__snap_unit_skip"] == "hour"
                kwargs[:snap] = snap_value * u"hr"
            elseif payload["Options__snap_unit_skip"] == "day"
                kwargs[:snap] = snap_value * u"d"
            end
        end
        
        if haskey(payload, "Options__index_skip")
            if occursin(".", payload["Options__index_skip"])
                kwargs[:index] = payload["Options__index_skip"]
            else
                kwargs[:index] = Symbol(payload["Options__index_skip"])
            end
        end

        if !isempty(payload["selected_targets"])
            kwargs[:target] = collect(payload["selected_targets"])
        end

        # if haskey(payload, "Snap__number_skip")
        #     kwargs[:target] = [:GDD, :cGDD]
        # end

        df = simulate(S; config=config, kwargs...) |> deunitfy

        # Convert the DataFrame to a JSON-friendly format
        columns = names(df)
        for column in columns
            replace!(df[!, column], Inf => 1e308)
            replace!(df[!, column], -Inf => -1e308)
        end
        data = [collect(row) for row in eachrow(df)]
        result = Dict("columns" => columns, "data" => data)
    
        return Json.json(Dict("status" => "Simulation complete", "results" => result))
    end

    up(async = false)
end