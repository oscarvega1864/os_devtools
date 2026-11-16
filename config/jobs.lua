-- Trabajos publicos (no son negocios): rangos fijos de menor a mayor, sueldo por rango que paga el ayuntamiento cada
-- Business.PayMinutes de servicio, y puntos de servicio en sus sedes (E para entrar o salir de servicio). Los rangos a
-- partir de "Boss" gestionan la plantilla con /trabajo (contratar a alguien cercano, ascender, despedir).
-- Si un punto no cuadra con el mapa del servidor (MLOs), un admin pone otro con /puntotrabajo <job> en su posicion.
OSDevtools = OSDevtools or {}
OSDevtools.PublicJobs = {
    police = { label = 'LSPD', kind = 'police', boss = 5,
        ranks = { 'cadete', 'agente', 'sargento', 'teniente', 'capitan', 'jefe' },
        salaries = { 300, 400, 500, 600, 750, 900 },
        duty = { { x = 441.02, y = -981.92, z = 30.69, label = 'Comisaria Mission Row' }, { x = -1093.0, y = -809.3, z = 19.28, label = 'Comisaria Vespucci' } } },
    sheriff = { label = 'BCSO', kind = 'police', boss = 5,
        ranks = { 'cadete', 'ayudante', 'sargento', 'teniente', 'capitan', 'sheriff' },
        salaries = { 300, 400, 500, 600, 750, 900 },
        duty = { { x = 1853.2, y = 3689.6, z = 34.27, label = 'Sheriff Sandy Shores' }, { x = -448.6, y = 6012.5, z = 31.72, label = 'Sheriff Paleto Bay' } } },
    fib = { label = 'FIB', kind = 'police', boss = 4,
        ranks = { 'agente', 'agente especial', 'supervisor', 'subdirector', 'director' },
        salaries = { 500, 650, 800, 950, 1100 },
        duty = { { x = 117.35, y = -740.0, z = 45.75, label = 'Edificio FIB' } } },
    fire = { label = 'Bomberos', kind = 'fire', boss = 4,
        ranks = { 'bombero en practicas', 'bombero', 'cabo', 'sargento', 'jefe de bomberos' },
        salaries = { 300, 400, 500, 650, 850 },
        duty = { { x = 199.8, y = -1643.9, z = 29.8, label = 'Parque de bomberos Davis' }, { x = 1693.0, y = 3584.4, z = 35.6, label = 'Parque de bomberos Sandy' } } },
    ems = { label = 'EMS', kind = 'ems', boss = 4,
        ranks = { 'tecnico', 'paramedico', 'enfermero', 'medico', 'jefe medico' },
        salaries = { 300, 400, 500, 700, 900 },
        duty = { { x = 298.6, y = -584.3, z = 43.26, label = 'Hospital Pillbox' }, { x = 1839.4, y = 3672.6, z = 34.28, label = 'Centro medico Sandy' } } },
}
