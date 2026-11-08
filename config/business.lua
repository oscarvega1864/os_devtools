OSDevtools=OSDevtools or {}
-- Categorias de /crearnegocio y su blip. Sprites y colores verificados en
-- https://docs.fivem.net/docs/game-references/blips/ (no hay sprite propio de restaurante).
OSDevtools.BusinessTypes={
    bar={label='Bar',sprite=93,color=5},                 -- radar_bar
    ltd={label='Tienda',sprite=52,color=2},              -- radar_crim_holdups (24/7)
    discoteca={label='Discoteca',sprite=614,color=27},   -- radar_bat_club_property
    seguridad={label='Seguridad',sprite=67,color=3},     -- radar_security_van
    medico={label='Medico',sprite=61,color=1},           -- radar_hospital
    restaurante={label='Restaurante',sprite=93,color=17},-- radar_bar en naranja
    compraventa={label='Compraventa',sprite=628,color=0} -- radar_bat_cash_reg
}
OSDevtools.BusinessBlipScale=0.8
-- Blips de propiedades (/crearpropiedad): radar_safehouse; verde a la venta, azul con propietario.
OSDevtools.PropertyBlipTypes={
    sale={label='Propiedad en venta',sprite=40,color=2},
    owned={label='Propiedad',sprite=40,color=3}
}
OSDevtools.PropertyBlipScale=0.7
