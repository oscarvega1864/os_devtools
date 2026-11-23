OSDevtools=OSDevtools or {}
-- spawnmanager: Devtools controla aparicion; external: el framework es el propietario.
OSDevtools.SpawnConfig={Mode='spawnmanager',TimeoutMilliseconds=20000}
-- Escena del selector de entrada: el personaje elegido (ped local, solo lo ve el jugador) de pie en la
-- salida de llegadas del LSIA, donde aparece por defecto. La camara se coloca delante segun su orientacion:
-- distance (m), height sobre el centro del ped, shift desplaza el encuadre para dejar al ped a la derecha
-- (el panel ocupa la izquierda) y fov. Para otro sitio basta cambiar ped (x,y,z como un punto de aparicion).
OSDevtools.SelectScene={ped={x=-1037.6,y=-2737.8,z=20.17,h=329.0},distance=3.6,height=0.15,shift=1.1,fov=40.0,
    scenario='WORLD_HUMAN_HANG_OUT_STREET'}
