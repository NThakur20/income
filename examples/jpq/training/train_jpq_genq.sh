CudaNum=0

for dataset in scifact
do
    # Prefix used for storing synthetic query generated for BEIR
    export PREFIX=gen

    #### (1) Convert BEIR dataset to JPQ Format ####
    OMP_NUM_THREADS=6 python -m income.jpq.beir.transform \
                      --dataset ${dataset} \
                      --output_dir "./datasets/${dataset}" \
                      --prefix  ${PREFIX} \

    #### (2) PREPROCESSING script tokenizes the queries and corpus ####
    CUDA_VISIBLE_DEVICES=${CudaNum} OMP_NUM_THREADS=6 python -m income.jpq.preprocess \
                                    --data_dir "./datasets/${dataset}" \
                                    --out_data_dir "./preprocessed/${dataset}"
    
    #### (3) INIT script trains the IVFPQ corpus faiss index ####
    CUDA_VISIBLE_DEVICES=${CudaNum} OMP_NUM_THREADS=6 python -m income.jpq.init \
        --preprocess_dir "./preprocessed/${dataset}" \
        --model_dir "sebastian-hofstaetter/distilbert-dot-tas_b-b256-msmarco" \
        --max_doc_length 350 \
        --output_dir "./init/${dataset}" \
        --subvector_num 96
    
    #### (4) TRAIN script trains TAS-B using Generated Queries (GenQ) ####
    CUDA_VISIBLE_DEVICES=${cudaNum} OMP_NUM_THREADS=6 python -m income.jpq.train_genq \
        --preprocess_dir "./preprocessed/${dataset}" \
        --model_save_dir "./final_models/${dataset}/genq" \
        --log_dir "./logs/${dataset}/log" \
        --init_index_path "./init/${dataset}/OPQ96,IVF1,PQ96x8.index" \
        --init_model_path "sebastian-hofstaetter/distilbert-dot-tas_b-b256-msmarco" \
        --lambda_cut 200 \
        --centroid_lr 1e-4 \
        --train_batch_size 256 \
        --num_train_epochs 1 \
        --gpu_search \
        --max_seq_length 64

    #### (5) Convert script converts TASBDot to JPQTower (Required for final evaluation) ####
    OMP_NUM_THREADS=6 python -m income.jpq.models.jpqtower_converter \
            --query_encoder_model "./final_models/${dataset}/genq/epoch-1" \
            --doc_encoder_model "sebastian-hofstaetter/distilbert-dot-tas_b-b256-msmarco" \
            --query_faiss_index "./final_models/${dataset}/genq/epoch-1/OPQ96,IVF1,PQ96x8.index" \
            --doc_faiss_index "./init/${dataset}/OPQ96,IVF1,PQ96x8.index" \
            --model_output_dir "./jpqtower/${dataset}/"

done