## function to generate predicted differences, standardized
standardized_differences = function(model1, model2, sigma=TRUE){
  pred1 = predict(model1, type="response")
  pred2 = predict(model2, type="response")
  differences = round(
    (quantile(abs(predict(model1, type="response") - 
                    predict(model2, type="response")))), digits=3)
  differences
}

#### make a custom labeller that removes "_binned"
custom.labeler = function(x){
  lapply(names(x),function(y){
    paste0(gsub("_binned", "", y),":\n", x[[y]])
  })
}



## function that does nested model comparisons on a single fitted model
nested_model_comparisons = function(object){
  
  ### extract necessary terms
  terms = attr(terms(object), "term.labels")
  
  ### temporary function that updates model
  removed.one.at.a.time = function(i, terms, object){
    new.f = as.formula(paste0(". ~ . -", terms[i]))
    new.object = update(object, new.f)
    list(
      rsq = summary(object)$r.squared - summary(new.object)$r.squared,
      bayes.factor = bf.bic(object, new.object, invert=FALSE)
    )
  }
  
  mc = t(sapply(1:length(terms), removed.one.at.a.time, terms=terms, object=object))
  mc = data.frame(cbind(terms,mc), stringsAsFactors = FALSE)
  mc
}

check.non.number = function(x){
  return.bool = ifelse(is.character(x) | is.factor(x), TRUE, FALSE)
  return.bool
}



variable_types = function(variables, data, return.names=F){
  if (length(variables)>0){
    characters = sapply(data[,variables, drop=F], check.non.number) 
    numbers = !characters
    if (return.names){
      list(characters=names(characters)[which(characters)], numbers=names(characters)[which(numbers)])  
    } else {
      list(characters=(characters), numbers=(numbers))  
    }
    
  }
}

#### if both numeric and factor, put numeric on x axis and factor as color/line
# predictors = c("Grad.School", "Years", "GPA", "Profession")
# data = graduate_income
# outcome = "Income"
make_flexplot_formula = function(predictors, outcome, data){
  
  # omit those variables not in the dataset
  nothere = which (!(predictors %in% names(data)))
  if (length(nothere)>0) predictors = predictors[-nothere]
  # if there's only one variable, make it
  if (length(predictors)==1){
    f = make.formula(outcome, predictors)
  } else {
  
    # algorithm that puts numeric in first slot, categorical in second slot
    favored.slots = c(1,4,3,2)
    vtypes = variable_types(predictors, data)
    numb = vtypes$numbers
    cat = vtypes$characters
    levs = sapply(data[,predictors], function(x) length(levels(x)))
    custom.sort = numb*1000 + cat*levs
    custom.sort = sort(custom.sort, decreasing=T)
    slots = names(custom.sort)[favored.slots]
    
    
    #### now create formula
    x = c(outcome, "~",slots[1], slots[2], "|", slots[3], slots[4])
    if (any(is.na(x)))  x = x[-which(is.na(x))]
    x = paste0(x, collapse="+")
    x = gsub("+|+", "|", x, fixed=T);x = gsub("+~+", "~", x, fixed=T)
    x = gsub("+|", "", x, fixed=T)
    f = as.formula(x)	
  }
  return(f)
}


# tested
extract_random_term = function(object) {
  #### extract formula
  form = as.character(formula(object))[3]
  
  #### identify random effects
  term.re = trimws(substr(form, regexpr("\\|", form)[1]+1, regexpr("\\)", form)[1]-1))		
  return(term.re)
}

# tested
test_same_class = function(model1, model2) {
  # if neither are lme4
  if (class(model1)[1] != "lmerMod" & class(model2)[1] != "lmerMod") return(NULL)
  
  # if one, but not both are lme4
  if (class(model1)[1] != class(model2)[1]) stop("It looks like you're trying to compare two models that are not both lme4 models. I can't do that! Sorry! \n\n Maybe you should go binge Netflix.")
  
  # if they have different random terms
  re_one = extract_random_term(model1)
  re_two = extract_random_term(model2)
  if (re_one != re_two) stop("Whoa there, tiger. You can't have different random effects for the two models.")
}


### return dataset containing factorized random effects (tested)
subset_random_model = function(object, d, samp.size = 3) {
  
  if (class(object)[1] == "lmerMod") {
    
    ## get random term
    term.re = extract_random_term(object)
    
    #### randomly sample the re terms and convert to numeric
    unique.terms = unique(d[,term.re])
    samp = sample(unique.terms, size=min(samp.size, length(unique.terms)))
    k = d[d[,term.re]%in%samp,]; k[,term.re] = as.factor(k[,term.re])
    return(k)
  }
  
  return(d)
}


prep.breaks = function(variable, data, breaks=NULL, bins=3){

		breaks = unlist(breaks)	
		if (is.null(bins)){bins=3}

		if (is.null(breaks)){
			quants = quantile(data[[variable]], seq(from=0, to=1, length.out=bins+1), na.rm=T)
			breaks = quants[!duplicated(quants)]
		} else {			
			#### give min as breaks, if the user doesn't
			if (min(breaks)>min(data[[variable]], na.rm=T)){
				breaks = c(min(data[[variable]], na.rm=T), breaks)
			}
			if (max(breaks,na.rm=T)<max(data[[variable]], na.rm=T)){
				breaks = c(breaks, max(data[[variable]], na.rm=T))
			}	
		}
		
		return(breaks)
		
}


bin.me = function(variable, data, bins=NULL, labels=NULL, breaks=NULL, check.breaks=TRUE, return.breaks=FALSE){


	### if they come as a list, unlist them
	if (is.list(breaks)){
		breaks = unlist(breaks)
	}
	if (is.list(labels)){
		labels = unlist(labels)
	}
	
	#### if they provide labels or breaks, choose the number of bins
	if (!is.null(labels)){
		bins = length(labels)
	} else if (!is.null(breaks)){
		bins = length(breaks)+1
	#### otherwise, set bins to 3
	} else {
		bins = 3
	}


	#### if they supply breaks, make sure there's a good min/max value	
	if (!is.null(breaks) & check.breaks){
		breaks = prep.breaks(variable, data, breaks)
	} 

  ### if we don't have breaks at this point, make some
  if (is.null(breaks)){
    breaks = quantile(as.numeric(data[[variable]]), seq(from=0, to=1, length.out=bins+1), na.rm=T)
  }
  
	### if they don't provide labels, make them easier to read (than R's native bin labels)\
	if (is.null(labels)){
		labels = 1:(length(breaks)-1)		
		for (i in 1:(length(breaks)-1)){
			labels[i] = paste0(round(breaks[i], digits=1), "-", round(breaks[i+1], digits=1))
		}
	}
	


	if (return.breaks){
		return(breaks)
	} else {
		binned.variable = cut(as.numeric(data[[variable]]), breaks, labels= labels, include.lowest=T, include.highest=T)
		binned.variable
	}
	
}


	### create custom function to sample data
sample.subset = function(sample, data){
	if (sample!=Inf){
		m = data[sample(1:nrow(data), size=sample),]
		
	} else {
		m = data
	}
	return(m)
}

	### if they don't want raw data, just make alpha = 0
raw.alph.func = function(raw.data,alpha=1){
	if (raw.data){
		alpha.raw = alpha
	} else {
		alpha.raw = 0
	}	
  alpha.raw
}


#match_jitter_categorical(.1)
match_jitter_categorical = function(x){
  if (is.null(x)){
    return(c(.2, 0))
  }else if (length(x)==2 & is.numeric(x))
    return(x)
  else if (is.numeric(x) & length(x)==1)
    return(c(x, 0))  
  else if (is.null(x) | x==TRUE)
    return(c(.2, 0))
  else if (!x)
    return(c(0,0))
  else
    stop("something's wrong with how you specified jittering.")
}

#match_jitter_categorical(.2)
#match_jitter_categorical(T)
#match_jitter_categorical(c(.2, .1))
#match_jitter_categorical(F)
#match_jitter_categorical(c(F,T))
#jitter = c(.2, .4); data=exercise_data; axis.var=c("therapy.type", "gender")
	#### points = the datapoints
points.func = function(axis.var, data, jitter){

  if (is.null(jitter) & !check.non.number(data[,axis.var[1]])){
    jitter = c(0,0)
  } else {
    jitter = match_jitter_categorical(jitter)
  }
  
  ### if they have two axis variables that are categorical
  if (length(axis.var)>1 & all(sapply(data[,axis.var, drop=F], check.non.number))){
    jit = paste0("geom_point(data=sample.subset(sample, ", deparse(substitute(data)), 
                 "), alpha=raw.alph.func(raw.data, alpha=alpha), position=position_jitterdodged(jitter.width=", jitter[1], ", jitter.height=", jitter[2], ", dodge.width=.5))")				
  
  ### if they have one categorical axis
  } else if (length(axis.var)==1 & check.non.number(data[,axis.var])){
    jit = paste0("geom_jitterd(data=sample.subset(sample, ", deparse(substitute(data)), "), alpha=raw.alph.func(raw.data, alpha=alpha), width=", jitter[1], ", height=", jitter[2], ")")				
  } else {  
    jit = paste0("geom_jitterd(data=sample.subset(sample, ", deparse(substitute(data)), "), alpha=raw.alph.func(raw.data, alpha=alpha), width=", jitter[1], ", height=", jitter[2], ")")				
  }
  
	#### return the jittered string
	return(jit)		
}

# points.func(axis.var="therapy.type", data=exercise_data, jitter=NULL)
# points.func("therapy.type", exercise_data, T)
# points.func("therapy.type", exercise_data, F)
# points.func("motivation", exercise_data, NULL)
# points.func(axis.var=c("motivation", "therapy.type"), data=exercise_data, jitter=NULL)
# points.func(c("gender", "therapy.type"), exercise_data, NULL)
# points.func(c("gender", "therapy.type"), exercise_data, c(.2, .1))


	#### this function converts a binary variable to a 1/0 for logistic regression
factor.to.logistic = function(data, outcome, labels=F){
  
  #### check if they have 2 unique values
  if (length(unique(data[,outcome]))!=2){
    stop("To fit a logistic curve, you must have only two levels of your outcome variable.")
  }	
  
  ### now do the converstion
  if (labels){
    unique(data[,outcome])
  } else {
    
    data[,outcome] = as.numeric(as.character(factor(data[,outcome], levels=unique(data[,outcome]), labels=c(0,1))))
    #data %>% dplyr::mutate(!!outcome := as.numeric(as.character(factor(!!as.name(outcome), levels=levels(!!as.name(outcome)), labels=c(0,1))))) 
    return(data)
  }
  
}


# factor_to_logistic_x = function(x){
#   
#   #### check if they have 2 unique values
#   if (length(unique(x))!=2){
#     stop("To fit a logistic curve, you must have only two levels of your outcome variable.")
#   }	
#   
#   ### now do the converstion
#     
#   x = as.numeric(as.character(factor(x, levels=levels(x), labels=c(0,1))))
#   x
# }


##' @importFrom MASS rlm	
#### identify the correct "fit"
fit.function = function(outcome, predictors, data, suppress_smooth=FALSE, method="loess", spread="sterr", mean.line=F, categorical=FALSE){
	
	if (is.numeric(data[,predictors]) & !categorical){
		if (suppress_smooth){
			fit.string = "xxxx"
		} else if (method=="logistic") {
	
			#### make sure there's only two levels
			if (length(unique(data[,outcome]))!=2){
				stop("To fit a logistic curve, you must have only two levels of your outcome variable.")
			}

			fit.string = 'geom_smooth(method = "glm", method.args = list(family = "binomial"), se = se)'			
		} else if (method=="rlm"){
			fit.string = 'geom_smooth(method = "rlm", se = se)'
		}else if (method=="poisson" | method=="Gamma") {
			#### specify the curve
			fit.string = 'geom_smooth(method = "glm", method.args = list(family = method), se = se)'
		} else if (method=="polynomial" | method == "quadratic"){
			fit.string = 'stat_smooth(method="lm", se=se, formula=y ~ poly(x, 2, raw=TRUE))'
		} else if (method=="cubic"){
			fit.string = 'stat_smooth(method="lm", se=se, formula=y ~ poly(x, 3, raw=TRUE))'
		} else if (method=="lm"){
			fit.string = 'stat_smooth(method="lm", se=se)'
		} else {
			fit.string = 'geom_smooth(method="loess", se=se)'
		}
		

		
	} else {
		
		if (suppress_smooth){
			summary1="xxxx"
			summary2="xxxx"
			sum.line="xxxx"						
		} else if (spread=="stdev"){
			summary1 = "stat_summary(fun.y='mean', geom='point', size=3, position=position_dodge(width=.5), color = '#bf0303')" 
			summary2 = "stat_summary(geom='errorbar', fun.ymin = function(z){mean(z)-sd(z)}, fun.ymax = function(z) {mean(z)+sd(z)}, fun.y=median, size = 1.25, width=.2, position=position_dodge(width=.5), color = '#bf0303')"
			if (mean.line){
				sum.line = 'stat_summary(aes_string(group= axis[2]), geom="line", fun.y="mean", position=position_dodge(width=.5), color = "#bf0303")'
			} else {
				sum.line='xxxx'
			}
		} else if (spread=="sterr"){	
			summary1 = "stat_summary(fun.y='mean', geom='point', size=3, position=position_dodge(width=.5), color = '#bf0303')"
			summary2 = "stat_summary(geom='errorbar', fun.ymin = function(z){mean(z)-1.96*(sd(z)/sqrt(length(z)-1))}, fun.ymax = function(z){mean(z)+1.96*(sd(z)/sqrt(length(z)-1))}, width=.2, size = 1.25, position=position_dodge(width=.2), color = '#bf0303')"
			if (mean.line){
				sum.line = 'stat_summary(aes_string(group= axis[2]), geom="line", fun.y="mean", position=position_dodge(width=.2), color = "#bf0303")'
			} else {
				sum.line='xxxx'
			}

		} else if (spread == "quartiles"){	
			summary1 = "stat_summary(fun.y='median', geom='point', size=3, position=position_dodge(width=.4), color = '#bf0303')" 
			summary2 = "stat_summary(geom='errorbar', fun.ymin = function(z){quantile(z, .25)},size = 1.25,  fun.ymax = function(z) {quantile(z, .75)}, fun.y=median, width=.2, position=position_dodge(width=.4), color = '#bf0303')"
			if (mean.line){
				sum.line = 'stat_summary(aes_string(group=axis[2]), geom="line", fun.y="median", position=position_dodge(width=.4), color = "#bf0303")'
			} else {
				sum.line='xxxx'
			}

		}
		
		fit.string = paste0(summary1, "+",summary2, "+", sum.line)		
		### check package version of ggplot2
		if (packageVersion("ggplot2")>"3.2.1"){
		  fit.string = gsub("fun.ymin", "fun.min", fit.string, fixed=T)
		  fit.string = gsub("fun.ymax", "fun.max", fit.string, fixed=T)
		  fit.string = gsub("fun.y", "fun", fit.string, fixed=T)
		} else {
		  fit.string
		}
		
	}
	
	return(fit.string)
	
}
