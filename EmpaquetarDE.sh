#!/bin/sh

# ########## #
# CONSTANTES #
# ########## #
readonly nombreOVF='PineTainer DE'

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

# Comprueba si un argumento es un entero mayor al segundo argumento
esNoEnteroOMenorOIgualQue() {
    case ${1#[-+]} in
        *[!0-9]* | '') return 0;;
        *) [ "$1" -le $2 ]
           return $?;;
    esac
}

# Establece el Internal Field Separator del terminal a \n. Meto la asignación dentro de una función
# para evitar que me dé algo al pensar que esta es la manera más estándar y eficiente de conseguir
# que IFS tome ese valor: si no lo veo, no lo siento
establecerIFSALF() {
    IFS='
'
}

# ################## #
# PROGRAMA PRINCIPAL #
# ################## #

# Comprobar que tenemos el software requerido
{ comprobarRequisito 'which' && comprobarRequisito 'sed' && comprobarRequisito 'split' && comprobarRequisito 'qemu-img' && comprobarRequisito 'sha1sum' && comprobarRequisito 'tar' && comprobarRequisito 'gzip'; } || exit $?
[ $(split --version | grep -c 'GNU') -eq 0 ] && { echo "! Se necesita la versión de 'split' de GNU, disponible en el paquete coreutils. Por favor, instala tal paquete antes de continuar."; exit 1; }

# Comprobar que tenemos los ficheros esqueleto necesarios
if [ -f "ova/skel/${nombreOVF}.ovf" -a -r "ova/skel/${nombreOVF}.ovf" ]; then
    # Mostrar un título
    echo "--- Empaquetador de $nombreOVF ---"
    echo

    # Pedir rutas de imágenes de disco
    i=0
    while
        printf 'Ruta hacia la imagen del disco %d de la máquina virtual (dejar vacía para no añadir más): ' $i
        # -r para ser más compatibles con SO que utilicen \ para separar componentes de rutas
        read -r imagen
        i=$((i + 1))
        [ -n "$imagen" ]
    do
        # Sorprendemente, meter literalmente el salto de línea en la cadena es la forma más sencilla, estándar
        # eficiente y horrible de conseguir que cualquier shell no le dé tratamientos especiales al salto de línea
        # durante sustituciones
        imagenes="$imagenes$imagen
"
    done
    printf '\n'

    # ¿Hay discos que convertir?
    if [ $i -gt 1 ]; then
        letra=a

        establecerIFSALF; set -f
        # Procesar las imágenes de disco
        for imagen in $imagenes; do
            unset IFS; set +f

            # Generar un nombre de fichero
            nombreFicheroDisco="${nombreOVF}-hd${letra}.vmdk"

            # Preguntarle al usuario el tamaño total del disco
            while esNoEnteroOMenorOIgualQue "$tamDisco" 512; do
                printf "Capacidad del disco $imagen en bytes: "
                read tamDisco
            done

            # Primeramente, convertir la imagen de disco al formato de distribución
            echo "> Convirtiendo ${imagen}..."
            qemu-img convert -p -O vmdk -o subformat=streamOptimized "$imagen" "ova/$nombreFicheroDisco" || { echo '! Ha ocurrido un error al convertir una imagen. Se aborta la ejecución del script.'; exit 2; }

            # Tenemos el disco convertido en el lugar correspondiente. Comprimirlo (qemu-img no soporta escribir imágenes a salida estándar)
            echo "> Comprimiendo ova/${nombreFicheroDisco}..."
            gzip -f -9 "ova/$nombreFicheroDisco" || { echo '! Ha ocurrido un error al comprimir una imagen. Se aborta la ejecución del script.'; exit 2; }

            # Si la imagen de disco comprimida ocupa más de 2 GiB, dividirla en fragmentos de 2 GiB - 16 MiB para facilitar su
            # distribución y ser más compatibles con diferentes sistemas de ficheros
            if [ $(wc -c "ova/${nombreFicheroDisco}.gz" | cut -d' ' -f1) -gt 2130706432 ]; then
                echo "> Dividiendo ova/${nombreFicheroDisco}.gz en fragmentos de 2 GiB - 16 MiB..."
                split --verbose -b 2032M -a 9 -d "ova/${nombreFicheroDisco}.gz" "ova/${nombreFicheroDisco}.gz."

                # Registrar entrada en el OVF teniendo en cuenta que el fichero está dividido en fragmentos
                ficherosDiscosOVF="$ficherosDiscos		<File ovf:id=\"$nombreFicheroDisco\" ovf:href=\"${nombreFicheroDisco}.gz\" ovf:size=\"$(wc -c "ova/${nombreFicheroDisco}.gz" | cut -d' ' -f1)\" ovf:chunkSize=\"2130706432\" ovf:compression=\"gzip\"/>
"

                # Eliminar fichero no dividido original, pues ya no nos hará falta
                echo "> Eliminando ova/${nombreFicheroDisco}.gz..."
                rm "ova/${nombreFicheroDisco}.gz" >/dev/null 2>&1

                # Añadir los fragmentos generados a la lista de ficheros de imágenes de disco
                partesGeneradas="ova/${nombreFicheroDisco}.gz.*"
                establecerIFSALF
                for parteImagen in $partesGeneradas; do
                    nombresFicherosDiscos="${nombresFicherosDiscos}$(basename "$parteImagen")
"
                done
                unset IFS
            else
                # Registrar entradas para los ficheros a generar (OVF XML y MF) sin más
                ficherosDiscosOVF="$ficherosDiscos		<File ovf:id=\"$nombreFicheroDisco\" ovf:href=\"${nombreFicheroDisco}.gz\" ovf:size=\"$(wc -c "ova/${nombreFicheroDisco}.gz" | cut -d' ' -f1)\" ovf:compression=\"gzip\"/>
"
                nombresFicherosDiscos="${nombresFicherosDiscos}${nombreFicheroDisco}.gz
"
            fi
            discosOVF="$discos		<Disk ovf:diskId=\"hd$letra\" ovf:fileRef=\"$nombreFicheroDisco\" ovf:capacity=\"$tamDisco\" ovf:format=\"http://www.vmware.com/interfaces/specifications/vmdk.html#streamOptimized\"/>
"

            # Calcular siguiente letra y olvidar el tamaño de disco actual
            letra=$(echo $letra | tr 'a-yA-Y' 'b-zB-Z')
            unset tamDisco
        done

        # Ahora generar el descriptor OVF a partir de la plantilla
        echo "> Generando descriptor OVF en ova/${nombreOVF}.ovf..."
        # Escapar porcentajes que pudiera haber en las variables
        ficherosDiscosOVF=$(echo "$ficherosDiscosOVF" | sed 's/%/\\%/g')
        discosOVF=$(echo "$discosOVF" | sed 's/%/\\%/g')
        # Generar el código sed de sustitución en la plantilla
        script="/^!FICHEROS_DISCOS!$/{ s%.*%$ficherosDiscosOVF%g;p;d }; /^!DISCOS!$/{ s%.*%$discosOVF%g;p;d }"
        # Aplicarlo sobre la plantilla
        sed "$script" "ova/skel/${nombreOVF}.ovf" > "ova/${nombreOVF}.ovf" || { echo '! Ha ocurrido un error al generar el descriptor OVF. Se aborta la ejecución del script.'; exit 3; }

        # Generar el manifiesto con las sumas de comprobación de todos los ficheros
        echo "> Generando manifiesto en ova/${nombreOVF}.mf..."
        : > "ova/${nombreOVF}.mf" || { echo '! Ha ocurrido un error de E/S al generar sumas de comprobación. Se aborta la ejecución del script.'; exit 4; }
        establecerIFSALF; set -f
        for fichero in "${nombreOVF}.ovf" $nombresFicherosDiscos; do
            unset IFS; set +f
            echo "> Calculando suma de comprobación SHA1 de ova/${fichero}..."
            sumaComprobacion=$(sha1sum "ova/$fichero" | cut -d' ' -f1)
            [ $? -eq 0 ] || { echo '! Ha ocurrido un error generar la suma de comprobación de una imagen. Se aborta la ejecución del script.'; exit 4; }
            echo "SHA1($fichero)= $sumaComprobacion" >> "ova/${nombreOVF}.mf" || { echo '! Ha ocurrido un error de E/S al generar la suma de comprobación de una imagen. Se aborta la ejecución del script.'; exit 4; }
        done

        # Crear el directorio donde dejaremos los ficheros generados a distribuir
        mkdir -p out >/dev/null 2>&1 || { echo "! Ha ocurrido un error al crear el directorio de salida. Se aborta la ejecución del script."; exit 4; }

        printf '¿Empaquetar ficheros generados en fichero OVA? (S/N): '
        read respuesta
        if [ "$respuesta" = 'S' -o "$respuesta" = 's' ]; then
            # Por último, generar el fichero OVA a partir de todos los ficheros generados anteriormente
            # Como un fichero OVA es un fichero TAR con sus contenidos en un orden determinado, inicialmente lo creamos vacío
            # Un fichero TAR vacío son 10 KiB de NUL
            echo '> Empaquetando ficheros generados en fichero out/${nombreOVF}.ova...'
            dd if=/dev/zero of="out/${nombreOVF}.ova" bs=10240 count=1 >/dev/null 2>&1 || { echo "! Ha ocurrido un error al empaquetar los ficheros del OVA. Se aborta la ejecución del script."; exit 5; }

            # Nos cambiamos temporalmente al directorio de ficheros de trabajo, para que la utilidad tar los vea en el directorio actual
            # y no genere directorios dentro del fichero
            cd ova

            # Ahora le añadimos los ficheros correspondientes, en el orden definido por el estándar OVF 1.0
            establecerIFSALF; set -f
            for fichero in "${nombreOVF}.ovf" "${nombreOVF}.mf" $nombresFicherosDiscos; do
                unset IFS; set +f

                # Comprobar qué implementación de tar tenemos, para hacernos a la idea del formato de su salida
                if [ $(tar --version | grep -c 'GNU tar') -gt 0 ]; then
                    # Tenemos la utilidad TAR de GNU
                    # "The TAR format used shall comply with the USTAR (Uniform Standard Tape Archive) format as defined by the POSIX IEEE 1003.1 standards group."
                    # - https://www.dmtf.org/sites/default/files/standards/documents/DSP0243_1.0.0.pdf
                    tar -H ustar -rvf "../out/${nombreOVF}.ova" "$fichero" || { echo "! Ha ocurrido un error al empaquetar los ficheros del OVA. Se aborta la ejecución del script."; cd ..; exit 5; }
                else
                    echo '* No se ha detectado la utilidad tar de GNU en el sistema. Se asumirá que cumple el estándar POSIX, y produce ficheros en formato USTAR.'
                    tar rvf "../out/${nombreOVF}.ova" "$fichero" || { echo "! Ha ocurrido un error al empaquetar los ficheros del OVA. Se aborta la ejecución del script."; cd ..; exit 5; }
                fi
            done

            cd ..
        else
            # No queremos empaquetar los ficheros generados en un OVA.
            # Simplemente mover los ficheros generados al directorio de salida
            establecerIFSALF; set -f
            for fichero in "${nombreOVF}.ovf" "${nombreOVF}.mf" $nombresFicherosDiscos; do
                unset IFS; set +f

                echo "> Moviendo ova/$fichero al directorio de salida out..."
                mv "ova/$fichero" out || { echo "! Ha ocurrido un error al mover un fichero generado al directorio de salida. Se aborta la ejecución del script."; exit 4; }
            done
        fi

        echo '- Script completado con éxito. Los ficheros a distribuir de la máquina virtual se encuentran en el directorio out.'
    else
        echo '- No se ha añadido por lo menos una imagen de disco que procesar.'
    fi
else
    echo '! Faltan los ficheros esqueleto necesarios para generar el fichero OVA de la máquina virtual.'
    exit 1
fi
