# Verificar sin una tercera ejecución rutinaria

Antes: responsable ejecuta sus pruebas → coordinador repite las suites →
verificador final vuelve a ejecutarlas. El protocolo permitía tres pasadas,
pero no se midió que todas ocurrieran sobre el mismo estado.

Ahora el coordinador inspecciona los comprobantes y revisa contratos entre
repositorios. No repite suites completas solo para consolidar. Se mantienen
las pruebas del responsable y la verificación final obligatoria del flujo
existente. Si falta evidencia o cambió el candidato, se solicita al responsable
la verificación afectada, sin crear otro escritor ni saltar el gate final.

No se implementó caché: un SHA idéntico no prueba entorno idéntico. Tampoco
se eliminaron revisiones explícitas ni requisitos SDD. Esta modificación no
autoriza pushes/merges adicionales, no sustituye protección ni modifica la
mecánica de publicación existente.

DevTools agrega `elapsed_seconds` a cada intento de verificación, incluyendo
preflight y rutas FAIL/TIMEOUT/BLOCKED/SKIPPED. Es tiempo monotónico del intento,
no tiempo puro del runner ni ahorro demostrado. Interpretar junto con estado,
`executed`, código de salida y revisión. Un skip medido sigue sin autorizar nada.

Pruebas: `python3 tests/verification_consolidation_test.py` comprueba las cinco
salidas y el contrato del protocolo con runners controlados; no simula evidencia
productiva. `python3 tests/cocoa_devtools_test.py` conserva las regresiones de
publicación con repositorios descartables. CI incluye el nuevo contrato.

Despliegue acotado: actualizar el protocolo de ambos clientes y el archivo de
DevTools solo si coinciden con la base conocida, conservando originales.
No reiniciar sesiones/servidores activos. Los procesos ya cargados pueden seguir
con el código anterior hasta su arranque normal; no afirmar recarga en caliente.
Rollback: restaurar los tres archivos respaldados solo si no cambiaron desde
la instalación; revertir fuente, pruebas y documentación como una unidad.
