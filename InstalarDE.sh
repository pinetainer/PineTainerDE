#!/bin/sh

# ########## #
# CONSTANTES #
# ########## #
readonly nombreArtefacto='PineTainer Development Environment'
readonly nombreMV='PineTainer DE'
readonly repositorioMV='pinetainer/PineTainerDE'
readonly fichRespuestaTemporal=/tmp/.pinetainer_answer
readonly dirDescargaPredeterminado=/tmp/PineTainer

# ######### #
# FUNCIONES #
# ######### #

# Comprueba que el sistema tenga un determinado programa
comprobarRequisito() {
    which $1 >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "! El programa '$1' no está instalado en el sistema, o no es accesible desde el directorio de trabajo actual. Por favor, instala el paquete correspondiente de ser necesario, y comprueba el valor de la variable de entorno \$PATH."
        return 1
    else
        return 0
    fi
}

# Comprueba que el sistema tenga todos los programas necesarios
comprobarRequisitos() {
    { comprobarRequisito 'which' && comprobarRequisito 'wget' && comprobarRequisito 'awk' && comprobarRequisito 'sed' && comprobarRequisito 'VBoxManage'; } || exit $?

    # Si stdbuf no está disponible, implementarlo como un "stub" que ejecuta su línea de comandos, ignorando el primer argumento
    comprobarRequisito 'stdbuf'
    if [ $? -ne 0 ]; then
        stdbuf() {
            shift
            eval $*
            return $?
        }
    fi
}

# Obtiene el ejecutable de tipo dialog a usar
obtenerDialog() {
    dialog=$(which dialog 2>/dev/null)
    if [ -z "$dialog" ]; then
        dialog=$(which whiptail 2>/dev/null)
    fi
}

# Se asegura de que la variable dirDescarga tome el valor apropiado, dada la entrada del usuario
obtenerDirectorioDescarga() {
    # Solo pedirlo al usuario si no lo tenemos ya, por haberlo leído de la línea de comandos
    if [ -z "$dirDescarga" ]; then
        preguntarVariable 'Directorio de descarga' 'Por favor, introduzca el directorio en el que descargar ficheros temporales de la máquina virtual.\n\nSi ya se descargaron ahí anteriormente, el script solamente seguirá descargando lo que haga falta.' 'Directorio de descarga de ficheros temporales de la máquina virtual' $dirDescargaPredeterminado
        codigoSalida=$?
        dirDescarga="$variable"

        # Inicializar dirDescarga al valor predeterminado si sigue vacío
        if [ -z "$dirDescarga" ]; then
            dirDescarga=$dirDescargaPredeterminado
        fi
    fi

    return $codigoSalida
}

# Elimina ficheros temporales creados al obtener datos del usuario, y limpiar la pantalla si
# el modo interactivo estaba activado
limpiezaSalida() {
    rm $fichRespuestaTemporal 2>/dev/null

    if [ -n "$modoInteractivo" ]; then
        clear
    fi

    exit $1
}

# Descarga un fichero en el directorio temporal de descargas
descargarFichero() {
    if [ -n "$modoInteractivo" ]; then
        wget -Nc --progress=dot:binary -P "$dirDescarga" "$1" 2>&1 | stdbuf -oL awk -Winteractive '
            # Cuando wget avise de que empieza la descarga, tenerlo en cuenta
            /^Saving to:/ {
                descargando=1
                next
            }

            # Mientras estemos descargando, extraer el porcentaje completado dado por wget
            # y mostrarlo por la salida estándar
            !/saved|skipping/ && $NF > 2 && descargando {
                if ($NF ~ /^.+=.+$/) {
                    camposFaltantes=1
                } else {
                    camposFaltantes=0
                }

                porcentaje=$(NF - 2 + camposFaltantes)
                sub(/%$/, "", porcentaje)
                print porcentaje
            }' \
        2>/dev/null | "$dialog" --backtitle "$nombreArtefacto" --title 'Descargando fichero' --gauge "Descargando $1 en $dirDescarga ... Por favor, espera." 8 64 0

        # Hack: considerar que la descarga siempre tuvo éxito. Al haber redirección mediante tuberías,
        # no podemos obtener el código de salida de wget de manera portable
        codigoSalida=0
    else
        echo "> Descargando $1 en $dirDescarga ..."
        # Intercambiar stderr y stdout, para que en stdout tengamos la información de progreso
        wget -Ncq -P "$dirDescarga" --show-progress "$1" 3<&2 2<&1 1<&3
        codigoSalida=$?
    fi

    return $codigoSalida
}

# Contacta la API de GitHub para obtener la lista de ficheros de la máquina virtual a descargar, y los descarga uno a uno.
# En caso de error, esta función no devuelve el control a quien la llama
descargarFicherosMV() {
    datosFicherosMV=$(wget -q -O - "https://api.github.com/repos/$repositorioMV/releases/latest")

    if [ $? -eq 0 ]; then
        # Interpretamos el JSON devuelto por la API para quedarnos con los URL de descarga
        urlFicheros=$(echo "$datosFicherosMV" | sed -n '/^ *"browser_download_url": *"..*" *$/{s/.*: *"//;s/" *$//;p}')

        # Como los ficheros no van a tener saltos de línea en su nombre, establecer el separador de campos al salto de línea es lo más seguro
        IFS='
'
        for url in $urlFicheros; do
            unset IFS
            descargarFichero "$url" || mostrarErrorYSalir "Ha ocurrido un error al descargar $url, o se ha interrumpido la operación. El entorno de desarrollo no fue configurado."
        fi
        unset IFS
    else
        mostrarErrorYSalir "Ha ocurrido un error al contactar a la API de GitHub para obtener los ficheros de $nombreArtefacto a descargar."
    fi
}

# Comprueba si una determinada MV existe en VirtualBox
existeMV() {
    VBoxManage showvminfo "$1" >/dev/null 2>&1
    return $?
}

# Importa una máquina virtual en formato OVA u OVF a VirtualBox
importarMV() {
    if [ -n "$modoInteractivo" ]; then
        VBoxManage import "$1" 3<&2 2<&1 1<&3 3>/dev/null | stdbuf -o0 awk -Winteractive '
            # Usar el punto como separador de registros
            BEGIN {
                RS="."
            }

            # Cuando VirtualBox muestre "OK", empezar a leer el progreso
            $NF > 0 && /^[[:space:]]*OK$/ {
                importando=1
                next
            }

            # Extraer porcentaje de avance de la salida del comando
            $NF > 0 && importando {
                gsub(/^[[:space:]]+|[[:space:]]+$|%/, "")
                print $0
            }' \
        2>/dev/null | "$dialog" --backtitle "$nombreArtefacto" --title 'Importando máquina virtual' --gauge "Importando la máquina virtual a VirtualBox... Esto puede tardar un rato." 8 64 0
    else
        echo "> Importando $1 a VirtualBox... Esto puede tardar un rato."
        VBoxManage import "$1"
    fi

    # Devolver éxito si una MV con el nombre esperado existe
    existeMV "$nombreMV"
    return $?
}

# Establecer los parámetros de configuración finales de la MV
establecerParametrosMV() {
    { VBoxManage modifyvm "$1" --pagefusion on --bioslogofadein off --bioslogofadeout off --bioslogodisplaytime 0 --nictype1 virtio --audio none && VBoxManage storagectl "$1" --name SATA --portcount 1 --bootable on; } >/dev/null 2>&1
    return $?
}

# Le pide al usuario una ruta para configurar una determinada carpeta compartida en una MV
configurarCarpetaCompartidaMV() {
    preguntarVariable 'Configurar carpeta compartida' "Puedes configurar la carpeta compartida $2 en $1.\n\nSi deseas usarla, introduce a continuación la ruta hacia el directorio que se expondrá al anfitrión.\n\nSi no deseas usarla, deja la ruta en blanco." "Ruta hacia carpeta compartida $2 en $1" ''

    if [ -n "$variable" ]; then
        VBoxManage sharedfolder add "$1" --name "$2" --hostpath "$variable"
        codigoSalida=$?
    else
        codigoSalida=0
    fi

    return $codigoSalida
}

# Pregunta al usuario si desea arrancar la MV
arrancarMV() {
    preguntarSiNo "Instalación completada con éxito. ¿Deseas iniciar $1 ahora?"

    if [ $? -eq 0 ]; then
        VBoxManage startvm "$1" >/dev/null 2>&1
        codigoSalida=$?
    else
        codigoSalida=0
    fi

    return $codigoSalida
}

# Borra una determinada MV de VirtualBox
borrarMV() {
     VBoxManage unregistervm --delete "$1" >/dev/null 2>&1
     return $?
}

# Pregunta al usuario el valor que debe de tomar una variable
preguntarVariable() {
    if [ -n "$modoInteractivo" ]; then
        if [ $(basename "$dialog") = dialog ]; then
            # Tenemos dialog
            "$dialog" --backtitle "$nombreArtefacto" --title "$1" --cancel-label 'Cancelar' --ok-label 'Continuar' \
                      --inputbox "$2" 16 48 "$4" 2>$fichRespuestaTemporal
            codigoSalida=$?
            variable=$(cat $fichRespuestaTemporal)
        else
            # Tenemos whiptail
            "$dialog" --backtitle "$nombreArtefacto" --title "$1" --cancel-button 'Cancelar' --ok-button 'Continuar' \
                      --inputbox "$2" 16 48 "$4" 2>$fichRespuestaTemporal
            codigoSalida=$?
            variable=$(cat $fichRespuestaTemporal)
        fi
    else
        printf '%s (%s): ' "$2" "$3"
        read variable
        codigoSalida=$?
    fi

    return $codigoSalida
}

# Muestra un mensaje de error usando dialog si está disponible, y después sale del script limpiando ficheros
# temporales
mostrarErrorYSalir() {
    if [ -n "$modoInteractivo" ]; then
        if [ $(basename "$dialog") = dialog ]; then
            "$dialog" --backtitle "$nombreArtefacto" --title 'Error' --ok-label 'Salir' --msgbox "$1" 16 48
        else
            # Whiptail
            "$dialog" --backtitle "$nombreArtefacto" --title 'Error' --ok-button 'Salir' --msgbox "$1" 16 48
        fi
    else
        echo "! $1"
    fi

    limpiezaSalida 2
}

# Muestra un mensaje de información al usuario, sin interrumpir la ejecución del script
mostrarMensaje() {
    if [ -n "$modoInteractivo" ]; then
        if [ $(basename "$dialog") = dialog ]; then
            "$dialog" --backtitle "$nombreArtefacto" --title "$nombreArtefacto" --ok-label 'Continuar' --msgbox "$1" 16 48
        else
            # Whiptail
            "$dialog" --backtitle "$nombreArtefacto" --title "$nombreArtefacto" --ok-button 'Continuar' --msgbox "$1" 16 48
        fi
    else
        echo "- $1"
    fi
}

# Lanza al usuario una pregunta del tipo Sí/No, y obtiene su respuesta en el código de salida de la función
preguntarSiNo() {
    if [ -z "$noPedirConfirmacion"]; then
        if [ -n "$modoInteractivo" ]; then
            if [ $(basename "$dialog") = dialog ]; then
                "$dialog" --backtitle "$nombreArtefacto" --title "$nombreArtefacto" --yes-label 'Sí' --no-label 'No' --yesno "$1" 16 48
            else
                "$dialog" --backtitle "$nombreArtefacto" --title "$nombreArtefacto" --yes-button 'Sí' --no-button 'No' --yesno "$1" 16 48
            fi
        else
            printf "%s (S/N): " "$1"
            read respuesta
            [ "$respuesta" = 's' -o "$respuesta" = 'S' ]
        fi
    else
        # Restaurar código de salida a 0, para interpretar respuesta afirmativa
        :
    fi

    return $?
}

# ################## #
# PROGRAMA PRINCIPAL #
# ################## #

# Comprobar los programas necesarios para la operación del script
comprobarRequisitos
obtenerDialog

# Si la salida estándar es un terminal y tenemos whiptail o dialog, usar modo interactivo por defecto
if [ -t 1 -a -n "$dialog" ]; then
    modoInteractivo=1
fi

# Leer argumentos de la línea de comandos
while getopts 'hbfd:' opcion; do
    case $opcion in
        b) unset modoInteractivo;;
        d) dirDescarga="$OPTARG";;
        f) noPedirConfirmacion=1;;
        h) echo "Este script descarga el $nombreArtefacto y lo configura para ser usado con VirtualBox."
           echo "Sintaxis: $0 [-hbf] [-d DIRECTORIO_DESCARGA]"
           echo
           echo "-h: muestra este mensaje de ayuda."
           echo "-b: activa el modo de procesamiento por lotes. En este modo el script siempre obtendrá parámetros desde entrada textual, y no desde una interfaz gráfica."
           echo "-f: no le pide confirmación al usuario para realizar ciertas acciones, asumiendo que acepta siempre. Usar con precaución."
           echo "-d DIRECTORIO_DESCARGA: el directorio de descarga donde guardar archivos temporales de la máquina virtual."
           exit;;
    esac
done

# Si ya existe la MV, preguntarle al usuario
existeMV "$nombreMV"
if [ $? -eq 0 ]; then
    preguntarSiNo "La máquina virtual ya podría estar creada en VirtualBox. ¿Deseas borrarla y volverla a crear? Esto eliminará los contenidos de su disco duro."
    if [ $? -eq 0 ]; then
        borrarMV "$nombreMV"
    else
        exit
    fi
fi

# Obtener el directorio de descarga a usar, y descargar en él la MV para importarla
obtenerDirectorioDescarga
if [ $? -eq 0 ]; then
    descargarFicherosMV
    importarMV "$dirDescarga/$nombreMV.ovf" || mostrarErrorYSalir "Ha ocurrido un error al importar la máquina virtual a VirtualBox, o se ha interrumpido la operación. El entorno de desarrollo no fue configurado."
    establecerParametrosMV "$nombreMV" || mostrarMensaje "No se han podido establecer algunos parámetros adicionales de la máquina virtual. Su funcionamiento podría no ser óptimo."
    configurarCarpetaCompartidaMV "$nombreMV" "PineTainer" || mostrarMensaje "Ha ocurrido un error configurando las carpetas compartidas de la máquina virtual. Por favor, hazlo manualmente."
    arrancarMV "$nombreMV" || mostrarMensaje "No se ha podido arrancar la máquina virtual. Por favor, hazlo desde VirtualBox, o vuelve a ejecutar este script si eso no es posible."
fi

# Eliminar ficheros temporales que pudiesen haber quedado
limpiezaSalida
