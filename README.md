# PineTainer DE
_PineTainer Development Environment_ es una máquina virtual preconfigurada para el desarrollo del sistema de ficheros raíz usado en la placa de PineTainer, mediante Buildroot.

En este repositorio se encuentran los scripts shell POSIX utilizados para la generación automática del Development Environment a partir de una máquina virtual ya existente, así como los scripts de instalación y configuración automática para el usuario final.

### Descripción de PineTainer DE
_PineTainer Development Environment_ es una máquina virtual basada en un sistema operativo Debian Buster x64, sin un entorno de escritorio gráfico. El sistema de ficheros raíz XFS, que contiene toda la información persistente del sistema, está montado sobre un volumen lógico de LVM con 16 GiB de capacidad total, de los cuales se usan 1,2 GiB. Por tanto, se puede expandir el sistema de ficheros en línea y de manera sencilla, de ser insuficientes esos 16 GiB.

Similarmente a Ubuntu, la conexión como usuario root está desactivada (excepto si el sistema invoca `sulogin`, lo cual ocurre en el modo de recuperación), y en su lugar existe un usuario "desarrollador" sin contraseña que puede ejecutar cualquier comando como root mediante `sudo`. Al arrancar el entorno de desarrollo, el sistema conecta automáticamente el usuario "desarrollador" al primer terminal virtual, que es el que está asociado a la pantalla por defecto.

Además del gestor de paquetes aptitude, están instalados todos los paquetes necesarios para usar Buildroot, incluyendo sus funcionalidades adicionales:
* ccache
* make
* binutils
* gcc (versión 8)
* g++
* patch
* git
* bzip2
* perl
* unzip
* rsync
* bc
* file
* libncurses5-dev
* python (versión 2.7)
* python-matplotlib
* python-numpy
* graphviz

También se han hecho algunas personalizaciones respecto a una instalación predeterminada de Debian. A saber:
* Se han eliminado paquetes innecesarios: reportbug, apt-changelog, tasksel, paquetes de localización, etc.
* BloqNum está activado por defecto en el primer terminal virtual.
* Los mensajes del kernel no se muestran en los terminales virtuales.
* La consola se ha configurado para usar la fuente Terminus y el juego de caracteres UTF-8.
* Disposición de teclado configurada en español.
* Montaje automático de la carpeta compartida con el anfitrión "PineTainer" en `~/PineTainer`, en cuanto el usuario "desarrollador" se conecta al sistema.
* Menú de GRUB oculto, con menos tiempo de espera antes de arrancar el SO, que establece una resolución del _framebuffer_ de DRM usado en el terminal virtual de 1152x864.
* Parámetros de línea de comandos de Linux modificados para arrancar en modo texto, con menores transiciones entre diferentes modos de vídeo.

### Obtener PineTainer DE
PineTainer DE se distribuye en [_Open Virtualization Format 1.0.0_](https://www.dmtf.org/sites/default/files/standards/documents/DSP0243_1.0.0.pdf) sin apenas extensiones de un hipervisor particular, por lo que aspira a ser compatible con todas las soluciones de virtualización que puedan importar máquinas virtuales en este formato. En particular, a fecha 30/06/2019, hemos comprobado que PineTainer DE puede usarse sin problemas en las últimas versiones de VirtualBox y VMware Workstation, pero hay más hipervisores con soporte para OVF disponibles.

Sin embargo, como compromiso entre tiempo de desarrollo, accesibilidad y coste, el script de instalación disponible en este repositorio solamente está diseñado para funcionar con un shell POSIX y el hipervisor VirtualBox. Asimismo, la propia máquina virtual tiene instaladas las _VirtualBox Guest Additions_ para dotarla de algunas funcionalidades prescindibles extra (por ejemplo, la compartición de carpetas con el anfitrión). En consecuencia, dependiendo del hipervisor usado y de la disponibilidad de un shell POSIX, hay varias formas de obtener _PineTainer Development Environment_. Si bien estas maneras de obtener el entorno de desarrollo no se excluyen entre sí, lo más razonable es usar la más específica para las circunstancias, ya que ofrecerá una mejor experiencia.

#### Obtener PineTainer DE sin un shell POSIX, o para un hipervisor distinto de VirtualBox
En caso de que un shell POSIX no esté disponible en el sistema (lo cual ocurre, por ejemplo, bajo un sistema operativo Windows sin _Windows Subsystem for Linux_ o Cygwin), o uses un hipervisor que no sea VirtualBox, la única manera de conseguir el DE es importando manualmente su OVF en tu hipervisor.

Los ficheros que definen la máquina virtual se encuentran disponibles para descargar en las [publicaciones de este repositorio](https://github.com/pinetainer/PineTainerDE/releases). Es recomendable usar siempre la última publicación disponible, a no ser que haya algún problema con ella. Todos los ficheros asociados a cada publicación (excepto el código fuente del repositorio) son necesarios para importar el fichero OVF que describe el Development Environment con éxito, siguiendo las instrucciones correspondientes para el hipervisor concreto.

#### Obtener PineTainer DE con un shell POSIX y VirtualBox
Si el sistema tiene un shell POSIX (porque usa Linux, una variante de Unix, _Windows Subsystem for Linux_, Cygwin o similares), y se pretende usar VirtualBox como hipervisor, entonces se puede usar el script de instalación automática disponible en este repositorio, `InstalarDE.sh`. Este script descarga los ficheros de la máquina virtual en un directorio temporal, la importa a VirtualBox, establece algunos parámetros para mejorar el rendimiento que no se pueden indicar en el fichero OVF y, opcionalmente, configura una carpeta compartida con el anfitrión e inicia el entorno de desarrollo.

Para que el script funcione se necesita, aparte de `VBoxManage` (incluido en VirtualBox) y el propio shell, `wget` y algunas herramientas más, que deberían de estar disponibles en la inmensa mayoría de sistemas (aunque si no lo están el script avisará de ello antes de hacer nada). Con las dependencias necesarias instaladas, iniciar el proceso de instalación se puede resumir en un simple comando:

```Shell session
$ wget -q -O - "https://raw.githubusercontent.com/pinetainer/PineTainerDE/master/InstalarDE.sh" | sh
```

El script de instalación acepta parámetros en la línea de comandos que influyen en su funcionamiento. Por ejemplo, por defecto el proceso de instalación es interactivo y utiliza `dialog` o `whiptail` si están disponibles, pero esto se puede evitar con la opción `-b`, haciéndolo más ameno a la interacción con otros scripts. La opción `-h` describe todas las opciones aceptadas y sus efectos.

#### Un curioso error al importar PineTainer DE a VirtualBox
Al importar la máquina virtual en versiones actuales de VirtualBox, `VBoxManage` siempre termina mostrando un error similar al siguiente, deteniendo el proceso y señalando un fallo al script de instalación:

```
Progress state: VBOX_E_OBJECT_NOT_FOUND
VBoxManage: error: Appliance import failed
VBoxManage: error: Error opening '/tmp/PineTainer/PineTainerDE-hda.vmdk.gz' for reading (VERR_FILE_NOT_FOUND)
VBoxManage: error: Details: code VBOX_E_OBJECT_NOT_FOUND (0x80bb0001), component ApplianceWrap, interface IAppliance
VBoxManage error: Context: "enum RTEXITCODE __cdecl handleImportAppliance(struct HandlerArg *)" at line 957 of file VBoxManageAppliance.cpp
```

Para posibilitar la distribución de la máquina virtual, ya que GitHub limita los archivos subidos a las publicaciones a algo menos de 2 GiB, y ser más compatibles con sistemas de ficheros como FAT, es necesario dividir sus imágenes de disco en varios ficheros, puesto que ocupan más de 2 GiB. Por suerte, el estándar OVF 1.0 permite dividir las imágenes, y especifica completamente cómo debe de proceder el hipervisor:

> Files referenced from the reference part may be split into chunks to accommodate file size restrictions on certain file systems. Chunking shall be indicated by the presence of the ovf:chunkSize attribute; the value of ovf:chunkSize shall be the size of each chunk, except the last chunk, which may be smaller. When ovf:chunkSize is specified, the File element shall reference a chunk file representing a chunk of the entire file. In this case, the value of the ovf:href attribute specifies only a part of the URL and the syntax for the URL resolving to the chunk file is given below. [...]

Sin embargo, [VirtualBox no implementa hoy por hoy la lógica necesaria para reconocer ficheros fragmentados](https://www.virtualbox.org/browser/vbox/trunk/src/VBox/Main/xml/ovfreader.cpp#L266), por lo que termina interpretando que un nombre de fichero sin los sufijos que indican su número de fragmento (.XXXXXXXXX) debe de existir. Naturalmente, tal fichero no existe, pues solo se distribuyen sus fragmentos, por lo que la ejecución se aborta con un error.

Aunque la solución trivial a este error es concatenar los fragmentos en orden con `cat` para obtener el fichero completo, hacerlo en el script de instalación sería extremadamente poco elegante, y neutralizaría los beneficios del manifiesto OVF, que permite detectar errores en la descarga. Por tanto, desde un punto de vista de mantenibilidad de este repositorio, no es una solución recomendable. La buena solución sería que VirtualBox implementase completamente el estándar, para lo que seguramente algún valiente tenga que enviar un parche que añada el soporte necesario para una funcionalidad que lleva 10 años especificada. Viva el código abierto.

### Distribuir PineTainer DE
Generar los ficheros de _PineTainer Development Environment_ para su distribución es un proceso simple, automatizado en parte por el script `EmpaquetarDE.sh`. Este script parte de un esqueleto del descriptor OVF de la máquina virtual situado en `ova/skel` y de las imágenes de sus discos, que convierte con `qemu-img`, `gzip` y `split` a un formato apropiado para su distribución. También genera el descriptor OVF final, crea un manifiesto con sumas de comprobación SHA1 y, opcionalmente, empaqueta todos los ficheros generados en un contenedor OVA (que no es más que un fichero USTAR). `EmpaquetarDE.sh` es un script interactivo, que pide datos al usuario mediante la entrada estándar y muestra información en la salida estándar, así que usarlo es intuitivo y no requiere mayores explicaciones.
