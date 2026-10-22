#Codigo de selecao
FICHEIRO=""

for arg in "$@"; do
    if [ "$arg" = "-p" ]; then
        FLAG_P=true
    fi
    if [ "$arg" = "-v" ]; then
        FLAG_V=true
    fi
    if [ "$arg" = "-f" ]; then
        FLAG_F=true
    fi
    if [[ "$arg" != "-"* ]]; then
        FICHEIRO="$arg"
    fi
done

if [[ "$FLAG_P" == true && "$FLAG_V" = true ]]; then
    exit
fi

if [[ "$FLAG_P" == false && "$FLAG_V" = false ]]; then
    $FLAG_V=true
fi

#Codigo de protecao
if [[ "$FLAG_P" == true ]]; then
    find "$FICHEIRO" > temp.txt

    ls -lAR "$FICHEIRO" > saida.txt

    while IFS= read -r linha; do
        md5sum "$linha" >> saida.txt
    done < "temp.txt"
fi

rm temp.txt

#Codigo de verificacao
