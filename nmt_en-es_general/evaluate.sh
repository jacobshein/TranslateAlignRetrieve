#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_DIR=~/projects/hutoma/nmt_en-es_general/env/bin
source $ENV_DIR/activate

MODEL_CHECKPOINT=$1
TEST_SRC=$2
TEST_TGT=$4
LANG_SRC=$3
LANG_TGT=$5

#Preprocess functions 
PREPROCESS_DIR=$SCRIPT_DIR/data/$LANG_SRC'2'$LANG_TGT/preprocess
MOSES_DIR=$SCRIPT_DIR/tools/mosesdecoder
SUBWORDNMT_DIR=$SCRIPT_DIR/tools/subword-nmt

preprocess_src() {
  INPUT_FILE=$1
  LANG=$2

  cat $INPUT_FILE |
  perl $MOSES_DIR/scripts/tokenizer/normalize-punctuation.perl -l $LANG |
  perl $MOSES_DIR/scripts/tokenizer/tokenizer.perl -l $LANG -no-escape |
  perl $MOSES_DIR/scripts/recaser/truecase.perl --model $PREPROCESS_DIR/truecase-model.$LANG_SRC |
  python $SUBWORDNMT_DIR/subword_nmt/apply_bpe.py -c $PREPROCESS_DIR/joint_bpe --vocabulary $PREPROCESS_DIR/vocab.$LANG --vocabulary-threshold 50
}

postprocess_pred() {
  INPUT_FILE=$1
  LANG=$2
  cat $INPUT_FILE |
  sed -r 's/(@@ )|(@@ ?$)//g' $INPUT_FILE |
  perl $MOSES_DIR/scripts/recaser/detruecase.perl |
  perl $MOSES_DIR/scripts/tokenizer/detokenizer.perl -l $LANG
}

#Select test set, preprocess src and translate
EVALUATE_DIR=$SCRIPT_DIR/data/$LANG_SRC'2'$LANG_TGT/evaluate/
mkdir -p $EVALUATE_DIR

#Preprocess TEST_SRC
TEST_SRC_BPE=$(mktemp)
preprocess_src $TEST_SRC $LANG_SRC > $TEST_SRC_BPE

#Translate Transformer
echo "Translate..."
PREDS_BPE=$(mktemp)
ONMT_DIR=$SCRIPT_DIR/tools/OpenNMT-py
python $ONMT_DIR/translate.py -model $MODEL_CHECKPOINT \
                                -src $TEST_SRC_BPE \
                                -output $PREDS_BPE \
				                        -verbose -replace_unk \
#                           -gpu 1

#Postprocess predictions
postprocess_pred $PREDS_BPE $LANG_TGT > $EVALUATE_DIR/$(basename $MODEL_CHECKPOINT).preds.$LANG_TGT

#Compute BLEU score with multi-bleu-detok
echo "Compute BLEU..."
BLEU_SCORE_DETOK=$(perl $MOSES_DIR/scripts/generic/multi-bleu-detok.perl -lc $TEST_TGT < \
                   $EVALUATE_DIR/$(basename $MODEL_CHECKPOINT).preds.$LANG_TGT \
		   | sed 's/,/\n/' | head -n 1 | grep -oP '[\d]{1,3}\.[\d]{2}+')

echo BLEU_SCORE_DETOK = $BLEU_SCORE_DETOK, MODEL = $(basename $MODEL_CHECKPOINT), TESTSET = $(realpath $TEST_SRC) \
                        | tee -a $EVALUATE_DIR/bleu

rm $PREDS_BPE $TEST_SRC_BPE

