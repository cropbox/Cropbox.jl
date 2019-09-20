@system Plant(Photosynthesis) begin
    calendar(context) ~ ::Calendar
    weather(context, calendar) ~ ::Weather
    sun(context, calendar, weather) ~ ::Sun
    soil(context) ~ ::Soil
    development(context, calendar, weather, sun, soil): dev ~ ::Development
    radiation(context, sun, development) ~ ::Radiation
end
