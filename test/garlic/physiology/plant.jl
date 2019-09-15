@system Plant(Photosynthesis) begin
    calendar(context) => Calendar(; context=context) ~ ::Calendar
    weather(context, calendar) => Weather(; context=context, calendar=calendar) ~ ::Weather
    sun(context, calendar, weather) => Sun(; context=context, calendar=calendar, weather=weather) ~ ::Sun
    soil(context) => Soil(; context=context) ~ ::Soil
    development(context, calendar, weather, sun, soil): dev => Development(; context=context, calendar=calendar, weather=weather, sun=sun, soil=soil) ~ ::Development
    radiation(context, sun, development) => Radiation(; context=context, sun=sun, development=development) ~ ::Radiation
end
