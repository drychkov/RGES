#correlate drug sensitivity with the potency to reserse disease gene expression (RGES)
#to reduce the computation time, only the drugs with sensitivty data were examined

#library(qvalue)
library("ROCR")
library("lsa")

cancer = "ER"
landmark = 1
#CMAP score output
output_path <- paste(cancer, "/lincs_score_", landmark, ".csv", sep="")

##############
cmap_score_new <- function(sig_up, sig_down, drug_signature) {
  #the old function does not support the input list with either all up genes or all down genes, this new function attempts to addess this, not fully validated
  #Note. I think that creating the anonymous functions in each iteration of the sapply's below is slowing things down. Predefine them eventually.
  #we also tweak a bit: whenever the sign of ks_up/ks_down, we minus the two scores.
  num_genes = nrow(drug_signature)
  ks_up <- 0
  ks_down <- 0
  connectivity_score <- 0
  
  # I think we are re-ranking because the GeneID mapping changed the original rank range
  drug_signature[,"rank"] <- rank(drug_signature[,"rank"])
  
  # Merge the drug signature with the disease signature by GeneID. This becomes the V(j) from the algorithm description
  up_tags_rank <- merge(drug_signature, sig_up, by.x = "ids", by.y = 1)
  down_tags_rank <- merge(drug_signature, sig_down, by.x = "ids", by.y = 1)
  
  up_tags_position <- sort(up_tags_rank$rank)
  down_tags_position <- sort(down_tags_rank$rank)
  
  num_tags_up <- length(up_tags_position)
  num_tags_down <- length(down_tags_position)
  
  # 
  if(num_tags_up > 1) {
    a_up <- 0
    b_up <- 0
    
    a_up <- max(sapply(1:num_tags_up,function(j) {
      j/num_tags_up - up_tags_position[j]/num_genes
    }))
    b_up <- max(sapply(1:num_tags_up,function(j) {
      up_tags_position[j]/num_genes - (j-1)/num_tags_up
    }))
    
    if(a_up > b_up) {
      ks_up <- a_up
    } else {
      ks_up <- -b_up
    }
  }else{
    ks_up <- 0
  }
  
  if (num_tags_down > 1){
    
    a_down <- 0
    b_down <- 0
    
    a_down <- max(sapply(1:num_tags_down,function(j) {
      j/num_tags_down - down_tags_position[j]/num_genes
    }))
    b_down <- max(sapply(1:num_tags_down,function(j) {
      down_tags_position[j]/num_genes - (j-1)/num_tags_down
    }))
    
    if(a_down > b_down) {
      ks_down <- a_down
    } else {
      ks_down <- -b_down
    }
  }else{
    ks_down <- 0
  }
  
  if (ks_up == 0 & ks_down != 0){ #only down gene inputed
    connectivity_score <- -ks_down 
  }else if (ks_up !=0 & ks_down == 0){ #only up gene inputed
    connectivity_score <- ks_up
  }else if (sum(sign(c(ks_down,ks_up))) == 0) {
    connectivity_score <- ks_up - ks_down # different signs
  }else{
    connectivity_score <- ks_up - ks_down
  }
  
  return(connectivity_score)
}

get.gene.list <- function(con){
  lincs_gene <- dbReadTable(con, "probe_id_info")
  
  return(lincs_gene$gene_id)
}

get.instance.sig <- function(id, con,  landmark=F){
  
  sig_file = paste("~/Documents/stanford/lincs/data/lincs/", id, ".txt", sep="")
  sig_value = NULL
  
  if (file.exists(sig_file)){
    sig_value= scan(sig_file )
    
    if (landmark){
      sig_value = sig_value[1:978]
    }
    
  }else{
    query <- paste("select * from proj_lincs.sig_values where id = ", id, sep="")
    rs <- dbSendQuery(con, query)
    result <- fetch(rs, n = -1)[1,]
    value <- as.double(unlist(strsplit(result[1,2], ",")))
    if (landmark == T){
      instance.sig <- data.frame(sig_id =  id, probe_id = seq(1, 978), value[1:978])      
    }else{
      instance.sig <- data.frame(sig_id = id, probe_id = seq(1, length(value)), value = value)      
    }
    dbClearResult(rs)  
    sig_value = instance.sig$value
  }
  return (sig_value)
}

##############
load("raw/lincs/lincs_signatures_cmpd_landmark.RData")
lincs_sig_info = read.csv("raw/lincs/lincs_sig_info.csv", stringsAsFactors=F)
lincs_drug_activity = read.csv(paste(cancer, "/lincs_drug_activity_confirmed.csv", sep=""), stringsAsFactors=F)
lincs_drug_activity = unique(subset(lincs_drug_activity, select=c("pert_iname", "doc_id", "standard_value", "standard_type", "description",    "organism",		"cell_line")))


if (landmark ==1){
  gene.list = rownames(lincs_signatures)
}else{
  gene.list = get.gene.list(con)  
}
sig.ids = lincs_sig_info$id[lincs_sig_info$pert_type == "trt_cp" & lincs_sig_info$is_gold == 1 & lincs_sig_info$id >0 & tolower(lincs_sig_info$pert_iname) %in% tolower(lincs_drug_activity$pert_iname)]


#load  genes
fromGSE62944 = F
if (fromGSE62944){
  dz_signature <- read.table(dz_sig_path,header=T,sep="\t")
  dz_signature <- subset(dz_signature, GeneID %in% gene.list)
}else{
  load(paste(cancer, '/', cancer, 'tcga_deseq_final.RData', sep='')) #tcga_deseq LIHC_sig_deseq_QC
  res$GeneID = sapply((res$id), function(id){unlist(strsplit(id, "\\|"))[2]})
  res$symbol = sapply((res$id), function(id){unlist(strsplit(id, "\\|"))[1]})
  dz_signature = subset(res, !is.na(padj) & !is.na(id) & id !='?' & padj < 1E-3 & abs(log2FoldChange) > 1.5 & abs(log2FoldChange) != Inf )
  dz_signature = subset(dz_signature, GeneID %in% gene.list )
  dz_signature$up_down = "up"
  dz_signature$up_down[dz_signature$log2FoldChange<0] = "down"
}

dz_genes_up <- subset(dz_signature,up_down=="up",select="GeneID")
dz_genes_down <- subset(dz_signature,up_down=="down",select="GeneID")

#only choose the top 100 genes
max_gene_size = 150
if (nrow(dz_genes_up)> max_gene_size){
  dz_genes_up <- data.frame(GeneID= dz_genes_up[1:max_gene_size,])
}
if (nrow(dz_genes_down)> max_gene_size){
  dz_genes_down <- data.frame(GeneID=dz_genes_down[1:max_gene_size,])
}


dz_cmap_scores = NULL
dz_pearsons = NULL
dz_spearmans = NULL
IQRs = NULL
cosines = NULL
count = 0
for (exp_id in sig.ids) {
  count = count + 1
  print(paste("Computing score for disease against cmap_experiment_id =",count))
  if (landmark ==1){
    sig <-  lincs_signatures[, as.character(exp_id)]
    cmap_exp_signature <- data.frame(gene.list,  rank(-1 * sig, ties.method="random"))    
  }else{
    sig <-  get.instance.sig(exp_id, con)
    cmap_exp_signature <- cbind(gene.list,  rank(-1 * sig, ties.method="random"))    
  }
  colnames(cmap_exp_signature) <- c("ids","rank")
  dz_cmap_scores = c(dz_cmap_scores, cmap_score_new(dz_genes_up,dz_genes_down,cmap_exp_signature))
  
 # compute spearman correlation and pearson correlation
  dz_sig_drug_sig = merge(dz_signature, data.frame(GeneID=gene.list, expr= sig), by="GeneID")
  dz_pearsons = c(dz_pearsons, cor(dz_sig_drug_sig$log2FoldChange, dz_sig_drug_sig$expr))
  cosines = c(cosines, cosine(dz_sig_drug_sig$log2FoldChange, dz_sig_drug_sig$expr))
  dz_spearmans = c(dz_spearmans, cor(dz_sig_drug_sig$log2FoldChange, dz_sig_drug_sig$expr, method="spearman"))
  IQRs = c(IQRs, IQR(sig))
  
}


results = data.frame(id = sig.ids, RGES = dz_cmap_scores, pearson = dz_pearsons,  spearman = dz_spearmans, cosine = cosines, iqr = IQRs)

results = merge(results, lincs_sig_info, by = "id")
results = results[order(results$RGES),]
write.csv(results, output_path)



