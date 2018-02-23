setwd("./data/")
args = commandArgs(trailingOnly=TRUE)
project = args[1]

metrics = read.csv(paste0(project,"_all_metrics.csv"))
clone_group = read.csv(paste0(project,"_volatile_clusters.csv"))
data = merge(clone_group[,c("CloneClassID",'GroupName')], metrics[,colnames(metrics) != "IntroducedAtVersion"])
ind_vars = colnames(data)[!(colnames(data) %in% c("CloneClassID","GroupName"))]

library(Hmisc)

vc <- varclus(~ ., data=data[,ind_vars], trans="abs")
# plot(vc)
threshold <- 0.7
# abline(h=1-threshold, col = "red", lty = 2)
reject = c()
for(i in 1:(length(ind_vars)-1) ){
  ind_1 = ind_vars[i]
  
  for(j in (i+1):length(ind_vars) ){
    ind_2 = ind_vars[j]
    if(vc$sim[i,j] >= threshold){
      reject = c(reject, ind_2)
    }
  }
}
reject = unique(reject)
ind_vars = ind_vars[!(ind_vars %in% reject)]



library(randomForest)
library(reshape2)
library(pROC)
library(plyr)
library(doParallel)
library(caret)
library(e1071)

cl <- makeCluster(10)
registerDoParallel(cl)

print("bootstrap running")
performance <- foreach(i=1:1000, .packages = c("randomForest","reshape2","pROC","plyr","caret","e1071"), .combine = "rbind") %dopar% {
  set.seed(i)
 #Generate a bootstrap sample with replacement
  indices <- sample(nrow(data), replace= T)
  
  training = data[indices,]
  testing = data[-unique(indices),]
  
  all.Perf = data.frame()
  
  for(model in c('RF','SVM','GLM')){
    if(model == "RF"){
      fit = randomForest(formula(paste("GroupName" , " ~ " , paste(ind_vars,collapse="+") )) , data=training, importance=T)
      prob = data.frame(CloneClassID=testing$CloneClassID, predict(fit, testing[,ind_vars], type="prob"))
    }else if(model == "SVM"){
      fit = svm(formula(paste("GroupName" , " ~ " , paste(ind_vars,collapse="+") )),  data=training, probability=TRUE)
      prob = data.frame(CloneClassID=testing$CloneClassID, attr(predict(fit, testing[,ind_vars], probability = TRUE), "probabilities"))
      
    }else if(model == "GLM"){
      training$IsShortLived = ifelse(training$GroupName == "Short-lived", 1, 0)
      fit = glm(formula(paste("IsShortLived" , " ~ " , paste(ind_vars,collapse="+") )), family = "binomial", data=training)
      prob = data.frame(CloneClassID=testing$CloneClassID, Prob = predict(fit, testing[,ind_vars], type="response"))
    }
    
    if(model == "RF" || model == "SVM"){
      votes = ddply(melt(prob, id.vars = "CloneClassID"), .(CloneClassID), function(x){
        vote = x[x$value == max(x$value),]
        if(nrow(vote) > 1){
          vote = vote[sample(nrow(vote),1),]
        }
        if(vote$variable == "Long.lived"){
          return(data.frame(PredictedGroup="Long-lived", Prob=vote$value))
        }else if(vote$variable == "Short.lived"){
          return(data.frame(PredictedGroup="Short-lived", Prob=vote$value))
        }
      } )
    }else if(model == "GLM"){
      votes = prob
      votes$PredictedGroup = "Long-lived"
      votes$PredictedGroup[votes$Prob > 0.5] = "Short-lived"
    }
    
    votes = merge(testing[,c('CloneClassID',"GroupName")], votes, by="CloneClassID")
    votes$PredictedGroup = factor(votes$PredictedGroup, levels=levels(votes$GroupName))
    votes$IsCorrect = (votes$GroupName == votes$PredictedGroup)
    
    focusGroup = "Short-lived"
    res = confusionMatrix(votes$PredictedGroup, votes$GroupName, positive = focusGroup)
    rf.perf = data.frame(
                         TruePositiveRate = res$byClass[attr(res$byClass,"names") == "Sensitivity"],
                         FalsePositiveRate = 1-res$byClass[attr(res$byClass,"names") == "Specificity"]
    )
    rf.perf$AUC = NA
    rf.perf$Brier = NA
    
    
      tmp = votes[,c('CloneClassID','GroupName','PredictedGroup','Prob')]
      tmp$outcome = 0
      tmp[votes$GroupName == focusGroup,]$outcome = 1
      tmp[tmp$PredictedGroup != focusGroup,]$Prob = 1-tmp[tmp$PredictedGroup != focusGroup,]$Prob

      
      #Get AUC
      a = auc(tmp$outcome,tmp$Prob)
      rf.perf$AUC = as.numeric(a) 
      
      rf.perf$Brier =  mean((tmp$Prob - tmp$outcome)^2)
    
    
    rf.perf = melt(rf.perf)
    rf.perf$Model = model
    
    all.Perf = rbind(all.Perf, rf.perf)
  }
  var.imp = as.data.frame(importance(fit,scale=F))
  write.table(var.imp,file = paste0(project,"_BinaryModel_var_importance.csv"), row.names = T, col.names = F, append = T, sep = ",")
  
  return(all.Perf)
}
stopCluster(cl)
write.csv(performance,file= paste0(project,"_BinaryModel_performance_3Models.csv"),row.names=F)





