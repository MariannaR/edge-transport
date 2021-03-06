#' Harmonize the energy intensities to match the IEA energy balances.
#'
#' We provide energy service trajectories. IEA energy balances have to be met and are *not*
#' consistent with GCAM intensities and ES trajectories.
#' Therefore we have to change energy intensities for historical timesteps and smoothly
#' change them to the GCAM/PSI values.
#'
#' @param tech_data iso level demand and intensity
#'
#' @importFrom rmndt magpie2dt


lvl1_IEAharmonization <- function(tech_data){
    te <- isbunk <- flow <- value <- `.` <- iso <- EJ_Mpkm <- conv_pkm_MJ <- subsector_L3 <- technology <- EJ_Mpkm.mean <- vehicle_type <- sector <- EJ_Mpkm_ave_adjusted <- Mpkm_tot <- factor_intensity <- EJ_Mpkm_ave <- EJ_Mpkm_adjusted <- lambda <- EJ_Mpkm_final <- EJ_tot_adjusted <- NULL 
    IEA <- calcOutput("IO", subtype = "IEA_output", aggregate = FALSE)
    IEA <- IEA[, 2005, c("fedie", "fepet", "fegat", "feelt"), pmatch = TRUE]

    IEA_dt <- magpie2dt(IEA, datacols=c("se", "fe", "te", "mod", "flow"), regioncol="iso", yearcol="year")
    IEA_dt <- IEA_dt[te != "dot"]  #delete fedie.dot
    IEA_dt[, isbunk := ifelse(grepl("BUNK", flow), flow, "short-medium")]

    IEA_dt[, c("se", "fe", "mod", "flow") := NULL]
    ## sum fossil liquids and biofuel to tdlit, and biogas and natural gas to tdgat
    IEA_dt[te %in% c("tdfospet", "tdfosdie", "tdbiopet", "tdbiodie"), te := "tdlit"]
    IEA_dt[te %in% c("tdfosgat", "tdbiogat"), te := "tdgat"]
    IEA_dt[, value := sum(value), by=.(iso, year, te, isbunk)]

    IEA_dt <- unique(IEA_dt)

    ## load pkm and intensity from GCAM database conversion rate MJ->EJ
    CONV_MJ_EJ <- 1e-12
    CONV_millionkm_km <- 1e6

    vehicle_intensity <- tech_data[["conv_pkm_mj"]]
    vehicle_intensity[, EJ_Mpkm := conv_pkm_MJ * CONV_millionkm_km * CONV_MJ_EJ][,conv_pkm_MJ:=NULL]

    ## output is given in million pkm
    tech_output <- tech_data[["tech_output"]]
    tech_output <- merge(tech_output, vehicle_intensity, all.x = TRUE,
                         by = intersect(colnames(tech_output), colnames(vehicle_intensity)))
    tech_output <- tech_output[!subsector_L3 %in% c("Cycle", "Walk"), ]  #no non-motorized

    ## use only 2005
    tech_output <- tech_output[year == 2005]

    setkey(tech_output, "technology")

    ## apply the IEA-friendly categories to tech_output
    elts <- c("Electric", "Adv-Electric", "BEV", "LA-BEV")
    tech_output[technology %in% elts, te := "tdelt"]
    gats <- "NG"
    tech_output[technology %in% gats, te := "tdgat"]

    ## all others are liquids (this includes some coal), as well as Hybrid Electric
    tech_output[is.na(te), te := "tdlit"]

    tech_output <- tech_output[tech_output > 0]

    dups <- duplicated(tech_output, by=c("iso", "technology", "vehicle_type"))
    if(any(dups)){
        warning("Duplicated techs found in supplied demand.")
        print(tech_output[dups])
        tech_output <- unique(tech_output, by=c("iso", "technology", "vehicle_type"))
    }


    ## if there is output but no intensity, we have to apply avg. intensity
    tech_output[, EJ_Mpkm.mean := mean(EJ_Mpkm, na.rm = T), by=.(year, technology, vehicle_type)
                ][is.na(EJ_Mpkm), EJ_Mpkm := EJ_Mpkm.mean
                  ][,EJ_Mpkm.mean := NULL]
    
    tech_output[, isbunk := ifelse(sector == "trn_aviation_intl", "AVBUNK", NA)]
    tech_output[, isbunk := ifelse(sector == "trn_shipping_intl", "MARBUNK", isbunk)]
    tech_output[, isbunk := ifelse(is.na(isbunk), "short-medium", isbunk)]


    tech_output_aggr <- tech_output[, .(Mpkm_tot = sum(tech_output),
                                        EJ_Mpkm_ave = sum(tech_output/sum(tech_output) * EJ_Mpkm)),
                                        by = c("iso", "year", "te", "isbunk")]

    ## merge with IEA
    tech_output_iea <- merge(IEA_dt, tech_output_aggr, all.y = TRUE, by = c("year","iso", "te", "isbunk"))

    ## inconsistencies such as IEA stating 0 feelt in AFG and GCAM saying that the
    ## total pkm there are1.791546e+07 are solved in the hard way, deleting the demand
    ## for the country that in theory is there according to GCAM
    tech_output_iea <- tech_output_iea[value > 0]

    ## calculate intensity factor
    tech_output_iea[, EJ_Mpkm_ave_adjusted := value/Mpkm_tot]
    ## calculate the ratio between the new and the old energy intensity
    tech_output_iea[, factor_intensity := EJ_Mpkm_ave_adjusted/EJ_Mpkm_ave]

    ## redistribute the energy intensity to the broader category they belong to, in
    ## the energy intensity dt
    tech_output <- merge(tech_output, tech_output_iea, all = FALSE,
                             by = c("year", "iso", "te", "isbunk"))

    ## multiply the energy intensities of the sub categories by the corresponding factor
    tech_output[, EJ_Mpkm_adjusted := EJ_Mpkm * factor_intensity]

    ## check: calculate EJ with rescaled intensity and compare to IEA
    tech_output[, EJ_tot_adjusted := sum(tech_output*EJ_Mpkm_adjusted), by=c("year", "iso", "te", "isbunk")]
    all.equal(tech_output$value, tech_output$EJ_tot_adjusted)

    ## remove all the columns that I don't need, including years (so to have it for all years)
    tech_output=tech_output[,c("iso","technology","vehicle_type","EJ_Mpkm_adjusted")]

    ## harmonize data
    merged_intensity <- tech_output[vehicle_intensity, on=c("iso", "technology", "vehicle_type")]

    ## if there is no harmonization data, lets use the existing one
    merged_intensity[is.na(EJ_Mpkm_adjusted), EJ_Mpkm_adjusted := EJ_Mpkm]

    ## phase-in time span
    delta <- 15

    ## lambda vectors (where to use adjusted values)
    merged_intensity[, lambda := 1]
    merged_intensity[year >= 2005,
                     lambda := ifelse(year <= 2005 + delta,
                     (2005 + delta - year)/delta, 0)]

    merged_intensity[, EJ_Mpkm_final := EJ_Mpkm * (1-lambda) + EJ_Mpkm_adjusted * lambda]
    
    ## delete columns not useful anymore
    merged_intensity[,c("EJ_Mpkm", "lambda", "EJ_Mpkm_adjusted")]=NULL
    
    return(merged_intensity)

}
