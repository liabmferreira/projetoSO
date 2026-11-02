#!bin/bash

#TODO: Verificar se estou a guardar todos os dados que o professor quer
#TODO: Criar a flag help
#TODO: Adicionar maneira de verificar adicao/remocao de diretorios, visto que estes nao ficam guardados na protecao, apenas ficheiros ficam
#TODO: Arrnajar maneira de indicar alteracoes, atualmente so indica se nada fois alterado, as alteracoes feitas ficam guardadas no documento /tmp/.vp.tmp
#TODO: O ficheiro da protecao n pode ter vp.tmp no nome
#TODO: Resolver problemas quando se usa o -e na verificacao

#Notas:
#Se um ficheiro foi excluidos quando foi criada a protecao tambem deve ser excluido 
#quando a protecao é verificada, senao vai dizer que esse ficheiro é novo


#Pattern dos ficheiros guardados
#nome |-| permissoes dono data/hora espaco hash

#Codigos de saida
#0 funcionamento normal
#1 pasta/ficheiro a proteger não encontrado
#2 A flag -p foi usada sem ficheiros/pastas para proteger
#3 A flag -e foi usada sem ficheiros/pastas para excluir
#4 A flag -f recebeu mais/menos de uma argumento
#5 O programa foi exxecutado em modo protecao -p e verificaco -v ao mesmo tempo
#6 Foi passada uma flag que não existe
#7 A flag -v recebeu argumentos
#8 A flag -f recebeu o nome de uma protecao que não existe
#9 A flag -s recebeu mais/menos de um argumento
#10 Tentativa de ler um ficheiro nao encriptado usando password
#11 Erro ao desencriptar o ficheiro
#12 O nome dos ficherios a gaurdar não pode conter " |-| "
#13 Tentativa de ler um ficheiro encriptado sem usar palavra passe
#14 Tentativa de passar argumentos para a flag -w
#15 Tentativa de passar argumentos para a flag -y
#16 Tentativa de usar o nome /tmp/.vp.tmp

FICHEIROSAVE="/tmp/.pdb" #O nome final deve ser ".pdb" por default
INCLUIDOS=()
EXCLUIDOS=()
ALTERADO=false
AVISOS=true
ENCRYPTED=false
OVERWRITE=false
PASSWORD=''

FLAG_P=false
FLAG_V=false

# #region Codigo de protecao
protect(){
    INCLUIDOS=("$@")

    #Chama a funcao que vai escrever na protecao toda a informacao de cada ficheiro pedido
    for file in "${INCLUIDOS[@]}"; do
        protectFile $file
    done

    #Guarda o nome dos ficheiros/pastas protegidos na ultima linha da protecao
    for file in "${INCLUIDOS[@]}"; do
        echo -n "$file " 
    done

} 

protectFile(){
    local FICHEIRO=$1

    #Coloca o nome de todos os ficheiros encontados na pasta/ficheiro numa array
    mapfile -t files_array < <(find "$FICHEIRO" -type f)

    #Caso haja ficheiros excluidos vai removelos da array
    cleaned_files_array=()
    if [ ! ${#EXCLUIDOS[@]} -eq 0 ]; then
        for file in "${files_array[@]}"; do
            excluded=false

            for excludedfile in "${EXCLUIDOS[@]}"; do

                #Permite a remocao de diretorios inteiros sem ter de escrever diretorio/*
                if [ -d $excludedfile ]; then
                    excludedfile="$excludedfile/*"
                fi

                if [[ "$file" == $excludedfile ]]; then
                    excluded=true
                    break
                fi
            done

            if [[ $excluded == "false" ]]; then
                cleaned_files_array+=("$file")
            fi

        done
        files_array=("${cleaned_files_array[@]}")
    fi

    #Ignora o ficheiro se ele for excluido por completo, retira-o dos incluidos para nao ser colocado no fim da protecao
    if [ ${#files_array[@]} -eq 0 ]; then
        INCLUIDOS=("${INCLUIDOS[@]/$FICHEIRO}") #Troca o nome do incluido por espaco vazio
        INCLUIDOS=(${INCLUIDOS[@]}) #Remove espacos vazios
        return 0
    fi

    #Gerar os hashes para todos os ficheiros e colocar numa array
    mapfile -t hashes_array < <(printf '%s\0' "${files_array[@]}" | xargs -0 sha256sum | cut -d' ' -f1)

    #Gerar todos os metadados e colocar numa array
    mapfile -t data_array < <(printf '%s\0' "${files_array[@]}" | xargs -0 stat -c "%A %U %y %s")

    #Escreve já formatado a informação de cada ficheiro da array no FICHEIROSAVE
    for i in "${!files_array[@]}"; do
        printf '%s |-| %s %s\n' "${files_array[i]}" "${data_array[i]}" "${hashes_array[i]}"
    done
}
# #endregion

# #region Codigo de Verificacao
verify(){
    local PROTECTIONFILE=$1
    local ORIGINALNAME=$1
    local PROTECTEDFILES=()

    #Verifica se a protecao que vai ser verificada existe
    if [ ! -e "$FICHEIROSAVE" ]; then
        [ "$AVISOS" = true ] && echo "A protecao $FICHEIROSAVE não existe"
        exit 8
    fi

    #Cria um ficheiro temporario desencriptado usado para verificacao caso o original esteja encriptado
    if [[ $ENCRYPTED == true ]]; then
        if file "$PROTECTIONFILE" | cut -d' ' -f2- | grep -q "PGP"; then

            #Desencripta o ficheiro, cria um ficheiro desencriptado usado para leitura, redireciona erros para a null para nao serem impressos
            gpg -q --batch --yes --passphrase "$PASSWORD" -d -o "/tmp/.vp.tmp.decrypted" "$PROTECTIONFILE" 2>/dev/null

            #Termina a execucao caso o exit code do gpg nao seja 0 (o gpg deu erro)
            if [[ $? != 0 ]]; then
                [ "$AVISOS" = true ] && echo "Erro na desencriptacao, verifique a palavra passe"
                exit 11
            fi

            PROTECTIONFILE="/tmp/.vp.tmp.decrypted"
        else
            [ "$AVISOS" = true ] && echo "Tentativa de ler um ficheiro não encriptado usando password"
            exit 10
        fi
    else
        #Verifica se tenta ler uma base de daodos encriptada sem ser em modo encriptado
        if file "$PROTECTIONFILE" | cut -d' ' -f2- | grep -q "PGP"; then
           [ "$AVISOS" = true ] && echo "Tentativa de ler um ficheiro encriptado em modo não encriptado" 
           exit 13
        fi
    fi

    protect $(tail -n 1 "$PROTECTIONFILE") > "/tmp/.vp.tmp"

    
    if  cmp -s "/tmp/.vp.tmp" "$PROTECTIONFILE"; then
        [ "$AVISOS" = true ] && echo "Os ficheiros não foram alterados" 
        rm -f "/tmp/.vp.tmp"
        exit 0
    fi

    head -n -1 "/tmp/.vp.tmp" | sort > "/tmp/.sort.vp.tmp"
    rm -f "/tmp/.vp.tmp"

    head -n -1 "$PROTECTIONFILE" | sort > "/tmp/.sort.stvp.tmp"

    #Procura os ficheiros novos
    [ "$AVISOS" = true ] && awk '{print "Foi adicionado o ficheiro " $1;}' <(comm -13 "/tmp/.sort.stvp.tmp" "/tmp/.sort.vp.tmp")

    #Procura os ficheiros removidos
    [ "$AVISOS" = true ] && awk '{print "Foi removido o ficheiro " $1;}' <(comm -23 "/tmp/.sort.stvp.tmp" "/tmp/.sort.vp.tmp")

    #Diz ao awk para dividir pelo "|-|" e depois dividir a informacao dos segundo espaco (informacao velha)
    #e do terceiro espaco (informacao nova) pelos espacos " " para que possa ser comparada
    [ "$AVISOS" = true ] && awk -F ' \\|-\\| ' ' 
    {
        # Divide a informacao antiga pelos epacos e coloca-a em variaveis
        split($2, info_antiga, " ");
        permissoes_antigas = info_antiga[1];
        dono_antigo = info_antiga[2];
        data_antiga = info_antiga[3];
        hora_antiga = info_antiga[4];
        fuso_antigo = info_antiga[5];
        espaco_antigo = info_antiga[6];
        hash_antigo = info_antiga[7];

        # Divide a informacao nova pelos espacos e coloca-a em variaveis
        split($3, info_nova, " ");
        permissoes_novas = info_nova[1];
        dono_novo = info_nova[2];
        data_nova = info_nova[3];
        hora_nova = info_nova[4];
        fuso_novo = info_nova[5];
        espaco_novo = info_nova[6];
        hash_novo = info_nova[7];

        #Compara as variaveis e imprime os resultados no terminal
        if (permissoes_antigas != permissoes_novas) { 
            print $1 ": as permissoes passaram de " permissoes_antigas " para " permissoes_novas;
        }

        if (dono_antigo != dono_novo) { 
            print $1 ": o dono passou de " dono_antigo " para " dono_novo;
        }

        if (data_antiga != data_nova || hora_antiga != hora_nova || fuso_antigo != fuso_novo) { 
            print $1 ": as data passou de " data_antiga " " hora_antiga " " fuso_antigo " para " data_nova " " hora_nova " " fuso_novo;
        }

        if (espaco_antigo != espaco_novo) { 
            print $1 ": o espaco passou de " espaco_antigo " bytes para " espaco_novo " bytes";
        }

        if (hash_antigo != hash_novo) { 
            print $1 ": o hash passou de " hash_antigo " para " hash_novo;
        }
    }' <(join ".sort.stvp.tmp" ".sort.vp.tmp")

    rm ".sort.stvp.tmp"
    rm ".sort.vp.tmp"
}

# #endregion

# #region Leitura e Interpretacao de flags
while getopts ":pef:vwhys:" arg; do
    case $arg in
        #Especifica 1 ou mais pastas/ficheiros para proteger
        p)
            while [[ "${!OPTIND}" ]] && [[ "${!OPTIND}" != -* ]]; do
                INCLUIDOS+=("${!OPTIND}")
                OPTIND=$((OPTIND + 1))
            done
            if [[ ${#INCLUIDOS[@]} < 1 ]]; then
                [ "$AVISOS" = true ] && echo "Tem de ser passado pelo menos um ficheiro para proteger"
                exit 2
            fi
            FLAG_P=true
        ;;

        #Compara os dados atuais com os que estão na proteção
        v)
            if [[ -n "${!OPTIND}" && "${!OPTIND}" != -* ]]; then
                [ "$AVISOS" = true ] && echo "A flag -v não aceita argumentos"
                exit 7
            fi
            FLAG_V=true
        ;;

        #Eclui ficheiros da proteção
        e)
            while [[ "${!OPTIND}" ]] && [[ "${!OPTIND}" != -* ]]; do
                EXCLUIDOS+=("${!OPTIND}")
                OPTIND=$((OPTIND + 1))
            done
            if [[ ${#EXCLUIDOS[@]} < 1 ]]; then
                [ "$AVISOS" = true ] && echo "Tem de ser passado pelo menos um ficheiro para excluir"
                exit 3
            fi
        ;;

        #Especifica o nome do ficheiro onde guardar/onde estao guardados
        f) 
            FICHEIROSAVE="${OPTARG}"

            #Evita que o utilizador use o nome temporario como nome da protecao, este nome e preciso para a verificacao
            if [ "$FICHEIROSAVE" == '/tmp/*vp.tmp' ]; then
                [ "$AVISOS" = true ] && echo "A protecao nao pode ter o nome /tmp/*vp.tmp"
                exit 16
            fi

            #Evita que, caso o utilizador coloque outra flag depois da flag -f, o programa identifique a segunda flag como argumento
            if [[ "$OPTARG" == -* ]]; then
                [ "$AVISOS" = true ] && echo "A flag -f aceita exatamente 1 argumento"
                exit 4
            fi
      
            #Verifica se a flag -f tem mais de um argumento
            proximo_arg="${!OPTIND}"
            if [[ -n "$proximo_arg" && "$proximo_arg" != -* ]]; then
                [ "$AVISOS" = true ] && echo "A flag -f aceita exatamente 1 argumento"
                exit 4
            fi
        ;;

        h)
            #TODO: help flag
        ;;

        w)
            if [[ -n "${!OPTIND}" && "${!OPTIND}" != -* ]]; then
                [ "$AVISOS" = true ] && echo "A flag -w não aceita argumentos"
                exit 14
            fi
            AVISOS=false
        ;;

        s)
            ENCRYPTED=true
            PASSWORD="${OPTARG}"

            #Evita que, caso o utilizador coloque outra flag depois da flag -s, o programa identifique a segunda flag como argumento
            if [[ "$OPTARG" == -* ]]; then
                [ "$AVISOS" = true ] && echo "A flag -s aceita exatamente 1 argumento"
                exit 9
            fi
      
            #Verifica se a flag -s tem mais de um argumento
            proximo_arg="${!OPTIND}"
            if [[ -n "$proximo_arg" && "$proximo_arg" != -* ]]; then
                [ "$AVISOS" = true ] && echo "A flag -s aceita exatamente 1 argumento"
                exit 9
            fi
        ;;

        y)
            if [[ -n "${!OPTIND}" && "${!OPTIND}" != -* ]]; then
                [ "$AVISOS" = true ] && echo "A flag -y não aceita argumentos"
                exit 15
            fi
            OVERWRITE=true
        ;;

        :)
            [ "$AVISOS" = true ] && echo "A flag -${OPTARG} recebe exatamente 1 argumento"

            if [ "$OPTARG" == "f" ]; then
                exit 4
            fi
            if [ "$OPTARG" == "s" ]; then
                exit 9
            fi
        ;;

        \?)
            [ "$AVISOS" = true ] && echo "A flag '-$OPTARG' nao existe"
            exit 6
        ;;
    esac
done

#Se existirem as flags de protecao "-p" e a de verificaco "-v" o comando não deve funcionar
if [[ "$FLAG_P" == true && "$FLAG_V" = true ]]; then
    [ "$AVISOS" = true ] && echo "ERRO: O programa foi executado em modo proteção (-p) e verificação (-v) ao mesmo tempo"
    exit 5
fi

#Se não existirem as flags de protecao "-p" nem a de verificaco "-v" corre em "-v" por standard
if [[ "$FLAG_P" == false && "$FLAG_V" = false ]]; then
    FLAG_V=true
fi

#Executa com a flag -p
if [[ "$FLAG_P" == true ]]; then

    #Verificacao de condicoes de erro
    for file in "${INCLUIDOS[@]}"; do

        #Da erro caso algum ficheiro nao exista
        if [ ! -e "$file" ]; then
            [ "$AVISOS" = true ] && echo "O ficheiro/pasta $file não existe"
            exit 1
        fi

        #Da erro caso algum ficheiro nos que foram incluidos tenha a seuqencia " |-| " no nome
        if find "$file" -type f | grep -qw "|-|"; then
            [ "$AVISOS" = true ] && echo "Os ficheiros não podem conter a sequencia ' |-| ' no nome"
            exit 12
        fi
    done

    #Pergunta ao utilizador se deseja subscrever uma protecao já existente
    if [[ $OVERWRITE == true ]]; then
        rm -f "$FICHEIROSAVE"
    else
        if [[ -f "$FICHEIROSAVE" ]]; then
            read -p "O ficheiro de protecao $FICHEIROSAVE já existe, deseja subscrever?(y/n) " res
            if [ "$res" != 'y' ]; then
                exit 0
            fi
            rm -f "$FICHEIROSAVE"
        fi
    fi

    #Cria um novo ficheiro de save vazio
    touch "$FICHEIROSAVE"

    #Corre o código que gera o texto e guarda o resultado no ficheiro
    protect "${INCLUIDOS[@]}" > "$FICHEIROSAVE"

    #Encripta o resultado caso o utilizador tenha usado a flag -s
    if [[ "$ENCRYPTED" == true ]]; then
        gpg --batch --yes --passphrase "$PASSWORD" -c "$FICHEIROSAVE" >> "$FICHEIROSAVE" && mv "$FICHEIROSAVE".gpg "$FICHEIROSAVE"
    fi

    chmod -w "$FICHEIROSAVE"

    [ "$AVISOS" = true ] && echo "A protecao $FICHEIROSAVE foi criada com $(wc -l < <(head -n -1 $FICHEIROSAVE)) ficheiros"
    exit 0
fi  

#Executa com a flag -v
if [[ "$FLAG_V" == true ]]; then
    verify "$FICHEIROSAVE"
fi 
# #endregion