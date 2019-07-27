extensions [array table gis csv]

globals
[
  ;reporters
  mean-white-saving              ;average developer saving
  mean-yellow-saving             ;average developer saving
  mean-orange-saving             ;average developer saving
  mean-violet-saving             ;average developer saving
  mean-gray-saving               ;average developer saving
  mean-professional-saving       ;average professionals saving
  mean-nonprofessional-saving    ;average non-professionals saving
  mean-professional-housing      ;average professionals housing
  mean-nonprofessional-housing   ;average non-professionals housing
  innercity-professional         ;number of inner-city professionals
  innercity-nonprofessional      ;number of inner-city non-professionals
  suburbia-professional          ;number of suburbia professionals
  suburbia-nonprofessional       ;number of suburbia non-professionals
  white-noi                      ;developer NOI
  yellow-noi                     ;developer NOI
  orange-noi                     ;developer NOI
  violet-noi                     ;developer NOI
  gray-noi                       ;developer NOI
;  gentrified_population          ;number of agents that have been gentrified
  sprawl_population              ;number of agents that have been sprawled
  emigration_population          ;number of agents that have been removed signifiying out-migration
  urban_growth_population        ;number of agents that have been added to the model
  ; ESRI related variables
  themap
  neighborhoods-dataset
  zones-dataset      ;ESRI
  studyarea-dataset

]

turtles-own          ;using Jackson's gentrification model
[
  ;developer          ;if true the agent is either yellow, violet, white, orange and gray
  ;professional       ;if true the person is green, red or blue (economic class)
  ;non-professional   ;if true the person is green, red or blue (economic class)
  tID                ; agent turtle ID
  budget             ;69% of annual income is annual budget, using Devisch agent decision-making
  ttype               ; dev;pro;nonpro
  income             ;average annual of 75628
  housing            ;28% of budget is housing (based on a 14868 annual housing cost)
  saving             ;every agent's income-budget
  lowerbound         ;mean - std of income distribution
  upperbound         ;mean + std of income distribution
  ;A-age             ;random between 0 and 85
  happy?             ;happy if neighboring same color and class agents >= 10%
  pID                ;it is the patch ID that this turtle resides
  similar-color      ;neighbors with similar colors
  similar-income     ;neighbors with similar incomes
  NOI                ;Net Operating Income of a project (NOI = Value * Cap Rate)
  near-CBD           ;preference to be near CBD
  low-rent           ;preference to pay lower rent
]


patches-own[
 ID           ;each patches ID related to a neighborhood, patch ID is identical with polygon ID_ID, using Yang Zhou's Segregation model
 properties
 occupied?    ;if it is occupied by a turtle
 density      ;number of agents in one area
 zID          ;each patches ID related to a zone
 nID          ;neighborhood ID
 p-age        ;property age up to 100 years old (using 0.04 lambda for property decay)
 psize        ;property size as square footage
 ptype        ;property type (C.condo/coop, S.detached/attached single family houses)
 price        ;overall value of the property for selling and buying
 PR           ;potential rent that arrived from the price factor using 32.03 price-to-rent ratio for DC
 CR           ;capitalized rent
 ;NR           ;neighborhood rent
 Rent-gap     ;RG based on Neil Smith's CR and PR
 ;vacancy-rate ;vacant properties divided by total properties
]



to setup
  clear-all
  random-seed 47820              ;random seed to make the experiments consistent when testing different parameters
 ; set gentrified_population 0    ;initialize reporters
  set sprawl_population 0        ;initialize reporters
  set emigration_population 0    ;initialize reporters

  load_data                      ;load map information and patch data
  setup-properties               ;initialize properties of each patch (house)
  setup-patches                  ;initialize properties of each patch (house)
  setup-developer                ;initialize developers properties
  setup-professional 1.0         ;add (1.0 * initial_population) number of professional agents
  setup-nonprofessional 1.0      ;add (1.0 * initial_population) number of non-professional agents
  update-turtles                 ;update agent properties
  reset-ticks
end

to go
  if all? turtles [ happy? ] [ stop ]                                    ;if all agents are happy, stop the program. Schelling's segregation model by Uri Wilensky
  emigration                                                             ; run emigration model in each iteration
  ;;; <<<calculate the density of each patch>>> ;;;
  let max_nID (max [nID] of patches with [zID > 30]) + 1
  let density_list array:from-list n-values max_nID [0]
  foreach n-values max_nID [?] [
    let number_of_turtles count turtles-on patches with [nID = ?]
    let dens (number_of_turtles / (count patches with [nID = ?]))
    array:set density_list ? dens
  ]
  ;;; <<<calculate the density of each patch>>> ;;;

  sprawl density_list                                                    ;pass density of each patch to see if we need sprawl

  move-turtles                                                           ;move agents based on their preferences

  developer-buy                                                          ;developers buy vacant places based on their saving

  update-turtles                                                         ;update turtles properties
  ;;; <<< update the housing price based on density and CR >>> ;;;
  ask patches with [zID > 30][
    set density array:item density_list nID
    set p-age p-age + 1
    set CR (PR * exp (-0.04 * min (list 100 p-age)))
    set Rent-gap ((PR - CR) / PR)
    set price (price-change-by-density density) * (CR * 12 * 32.02) ; more dense area have higher prices
  ]
  ;;; <<< update the housing price based on density and CR >>> ;;;

  get-info
  ;;; <<< urban growth every 15 years >>> ;;;
  ;if ticks != 0 and (remainder ticks 15) = 0
  ;changed to one year rate
  setup-professional ug_rate / 15
  setup-nonprofessional ug_rate / 15

  ;;; <<< gentrification by demand every 15 years >>> ;;;
  ; if ticks != 0 and (remainder ticks 15) = 0 [
    ;  gen_demand
  ; ]
  export-patches-vals
  export-turtles-vals

  tick
end

;;; load the map from shape file
to load_data
    set neighborhoods-dataset gis:load-dataset "data/Neighborhoods.shp"
    set zones-dataset gis:load-dataset "data/Zones.shp"
    set studyarea-dataset gis:load-dataset "data/StudyArea.shp"
    gis:set-world-envelope gis:envelope-of studyarea-dataset
    gis:set-drawing-color white
    gis:draw neighborhoods-dataset 1
    gis:draw zones-dataset 1
    gis:apply-coverage zones-dataset "BUFF_DIST" zID
    gis:apply-coverage neighborhoods-dataset "INPUT_FID" nID
    ;print gis:property-names zones-dataset

end


;;; for each patch (house), set a specific size, price, and PR
to setup-properties          ;using Smith's rent gap theory (capitalized & potential rent and decay factor)
  ask patches with [zID = 60] [set ptype "C"              ;inner-city condo/coop
                                             set psize random-normal 926.96 31.26
                                             set price random-normal 492867 14715.43
                                             set PR (1.0 * price / (12 * 32.02))] ; bid rent theory (1.0)

  ask patches with [zID = 90] [set ptype "S"              ;suburban dettached/attached single family house
                                             set psize random-normal 1650.40 504.14
                                             set price random-normal 769387 201379.80
                                             set PR (0.95 * price / (12 * 32.02))] ; bid rent theory (0.95)

  ask patches with [zID > 30] [set p-age random 100
                               set CR (PR * exp (-0.04 * p-age))   ;decline of CR through time. (Diappi and Bolchi model)
                               set Rent-gap ((PR - CR) / PR)
                               ]

end


;;; for each patch (house), set their color to defaul and make the vacant
to setup-patches
  (foreach (sort patches) (n-values count patches [?]) [
    ask ?1 [ set id ?2 ]
  ])
  ask patches with [ ptype = "C" or ptype = "S"] [set pcolor 3]
  ask patches with [ zID = 30] [set pcolor black]
  ask patches with [ID >= 0] [set occupied? false]

end

;;; setup properties of each developer
to setup-developer
  crt 1 [set color yellow set ttype "dev" set ID who]
  crt 1 [set color violet set ttype "dev" set ID who]
  crt 1 [set color white set ttype "dev" set ID who]
  crt 1 [set color orange set ttype "dev" set ID who]
  crt 1 [set color gray set ttype "dev" set ID who]
  ask turtles with [ttype = "dev"] [
    set tID who
    set shape "person"
    set size 5
    set happy? true
    set income random-normal 5000000 4000000       ;assuming developers have an initial income between 1 million and 10 million
    while [income < 0] [set income random-normal 5000000 4000000]
    set saving income
    set budget (income * 0.69)
    set NOI 0
  ]
  ask turtles with [ttype = "dev"] [move-to one-of patches with [zID = 30]]
end

;;; add and setup properties of professionals
to setup-professional [rate]
  ; for each color (red, green, blue), we create initial_population/2 agents for professionals
  crt round (rate * initial_population / 2) [   ; half the initial_population is professional and half of them are non-professional
    set tID who
    set ttype "pro"
    set color green
    set happy? false
    set lowerbound 117086
    set upperbound 158542
    set income random-normal 137814 20728
    set budget (income * 0.69)
    set housing (budget * 0.28)
    set saving (income - budget)
    set shape "person"
    set size 5
    let CBD-interest random 100  ;setting the near-CBD preference
    ifelse CBD-interest > 30     ;if number is more than 30% then the agent has a preference to be near CBD, if less than 30%, the agent doesn't prefer that
     [set near-CBD 1]
     [set near-CBD 0]
    let low-rent-perc random 100  ;setting the near-CBD preference
    ifelse low-rent-perc < 30     ;if number is more than 30% then the agent has a preference to pay low rent, if less than 30%, the agent doesn't prefer that
     [set low-rent 1]
     [set low-rent 0]
    let target one-of patches with [zID > 30 and occupied? = false]
    let moved-price [price] of target
    move-to target
    ;if this patch is already developed by a developer, add the price to its saving
    ask patch-here[
      set occupied? true
      if pcolor != 3 [ask turtles with [color = pcolor] [set saving (saving + moved-price)]]
    ]
    set housing (housing - moved-price)
    set pID [ID] of patch-here
  ]
  crt round (rate * initial_population / 2) [
    set tID who
    set color red
    set ttype "pro"
    set happy? false
    set lowerbound 117086
    set upperbound 158542
    set income random-normal 137814 20728
    set budget (income * 0.69)
    set housing (budget * 0.28)
    set saving (income - budget)
    set shape "person"
    set size 5
    let CBD-interest random 100  ;setting the near-CBD preference
    ifelse CBD-interest > 30     ;if number is more than 30% then the agent has a preference to be near CBD, if less than 30%, the agent doesn't prefer that
     [set near-CBD 1]
     [set near-CBD 0]
    let low-rent-perc random 100  ;setting the near-CBD preference
    ifelse low-rent-perc < 30     ;if number is more than 30% then the agent has a preference to pay low rent, if less than 30%, the agent doesn't prefer that
     [set low-rent 1]
     [set low-rent 0]
    let target one-of patches with [zID  > 30 and occupied? = false]
    let moved-price [price] of target
    move-to target
    ;if this patch is already developed by a developer, add the price to its saving
    ask patch-here[
      set occupied? true
      if pcolor != 3 [ask turtles with [color = pcolor] [set saving (saving + moved-price)]]
    ]
    set housing (housing - moved-price)
    set pID [ID] of patch-here
  ]
  crt round (rate * initial_population / 2) [
    set tID who
    set color blue
    set ttype "pro"
    set happy? false
    set lowerbound 117086
    set upperbound 158542
    set income random-normal 137814 20728
    set budget (income * 0.69)
    set housing (budget * 0.28)
    set saving (income - budget)
    set shape "person"
    set size 5
    let CBD-interest random 100  ;setting the near-CBD preference
    ifelse CBD-interest > 30     ;if number is more than 30% then the agent has a preference to be near CBD, if less than 30%, the agent doesn't prefer that
     [set near-CBD 1]
     [set near-CBD 0]
    let low-rent-perc random 100  ;setting the near-CBD preference
    ifelse low-rent-perc < 30     ;if number is more than 30% then the agent has a preference to pay low rent, if less than 30%, the agent doesn't prefer that
     [set low-rent 1]
     [set low-rent 0]
    let target one-of patches with [zID  > 30 and occupied? = false]
    let moved-price [price] of target
    move-to target
    ;if this patch is already developed by a developer, add the price to its saving
    ask patch-here[
      set occupied? true
      if pcolor != 3 [ask turtles with [color = pcolor] [set saving (saving + moved-price)]]
    ]
    set housing (housing - moved-price)
    set pID [ID] of patch-here
  ]
end

;;; add and setup properties of professionals
to setup-nonprofessional [rate]
  ; for each color (red, green, blue), we create initial_population/2 agents for non-professionals
  crt round (rate * initial_population / 2) [
    set tID who
    set color red
    set ttype "nonpro"
    set lowerbound 31876
    set upperbound 53752
    set income random-normal 42814 10938
    set budget (income * 0.69)
    set housing (budget * 0.28)
    set saving (income - budget)
    set shape "person"
    set size 5
    let CBD-interest random 100  ;setting the near-CBD preference
    ifelse CBD-interest > 30     ;if number is more than 30% then the agent has a preference to be near CBD, if less than 30%, the agent doesn't prefer that
     [set near-CBD 1]
     [set near-CBD 0]
    let low-rent-perc random 100  ;setting the near-CBD preference
    ifelse low-rent-perc < 30     ;if number is more than 30% then the agent has a preference to pay low rent, if less than 30%, the agent doesn't prefer that
     [set low-rent 1]
     [set low-rent 0]
    let target one-of patches with [zID  > 30 and occupied? = false]
    let moved-price [price] of target
    move-to target
    ;if this patch is already developed by a developer, add the price to its saving
    ask patch-here[
      set occupied? true
      if pcolor != 3 [ask turtles with [color = pcolor] [set saving (saving + moved-price)]]
    ]
    set housing (housing - moved-price)
    set pID [ID] of patch-here
  ]
  crt round (rate * initial_population / 2) [
    set tID who
    set color green
    set ttype "nonpro"
    set lowerbound 31876
    set upperbound 53752
    set income random-normal 42814 10938
    set budget (income * 0.69)
    set housing (budget * 0.28)
    set saving (income - budget)
    set shape "person"
    set size 5
    let CBD-interest random 100  ;setting the near-CBD preference
    ifelse CBD-interest > 30     ;if number is more than 30% then the agent has a preference to be near CBD, if less than 30%, the agent doesn't prefer that
     [set near-CBD 1]
     [set near-CBD 0]
    let low-rent-perc random 100  ;setting the near-CBD preference
    ifelse low-rent-perc < 30     ;if number is more than 30% then the agent has a preference to pay low rent, if less than 30%, the agent doesn't prefer that
     [set low-rent 1]
     [set low-rent 0]
    let target one-of patches with [zID  > 30 and occupied? = false]
    let moved-price [price] of target
    move-to target
    ;if this patch is already developed by a developer, add the price to its saving
    ask patch-here[
      set occupied? true
      if pcolor != 3 [ask turtles with [color = pcolor] [set saving (saving + moved-price)]]
    ]
    set housing (housing - moved-price)
    set pID [ID] of patch-here
  ]
  crt round (rate * initial_population / 2) [
    set tID who
    set color blue
    set ttype "nonpro"
    set lowerbound 31876
    set upperbound 53752
    set income random-normal 42814 10938
    set budget (income * 0.69)
    set housing (budget * 0.28)
    set saving (income - budget)
    set shape "person"
    set size 5
    let CBD-interest random 100  ;setting the near-CBD preference
    ifelse CBD-interest > 30     ;if number is more than 30% then the agent has a preference to be near CBD, if less than 30%, the agent doesn't prefer that
     [set near-CBD 1]
     [set near-CBD 0]
    let low-rent-perc random 100  ;setting the near-CBD preference
    ifelse low-rent-perc < 30     ;if number is more than 30% then the agent has a preference to pay low rent, if less than 30%, the agent doesn't prefer that
     [set low-rent 1]
     [set low-rent 0]
    let target one-of patches with [zID  > 30 and occupied? = false]
    let moved-price [price] of target
    move-to target
    ;if this patch is already developed by a developer, add the price to its saving
    ask patch-here[
      set occupied? true
      if pcolor != 3 [ask turtles with [color = pcolor] [set saving (saving + moved-price)]]
    ]
    set housing (housing - moved-price)
    set pID [ID] of patch-here
  ]
end


;to gen_demand
 ; let sorted_turtles sort-on [income] turtles with [zID = 90]                                            ;sort the agents in suburbia based on their income
  ;let sublist_sorted_turtles sublist sorted_turtles 0 round (gen_rate * count turtles with [zID = 90])   ;select the lowest income agent based on gen_rate
  ;set gentrified_population gentrified_population + (round (gen_rate * count turtles with [zID = 90]))   ;update the reporter for the number of gentrified agents
  ;;; <<< start moving low income agents to inner-city >>> ;;;
  ;foreach sublist_sorted_turtles[
   ; ask ?1 [
    ;  let turtle-saving housing
     ; let target one-of patches with [zID = 60 and occupied? = false and price < turtle-saving]
      ;if target != nobody [
       ; ask patch-here[set occupied? false]
        ;move-to target
        ;let moved-price [price] of target
        ;if this patch is already developed by a developer, add the price to its saving
        ;ask patch-here [
         ; set occupied? true
          ;if pcolor != 3 [ask turtles with [color = pcolor] [set saving (saving + moved-price)]]
        ;]
        ;set pID [ID] of patch-here
        ;set housing (housing - moved-price) ;developer sell
      ;]
    ;]
  ;]
;end


to sprawl [density_list]
  foreach n-values (array:length density_list) [?][
    let patch_density array:item density_list ?
    if patch_density > sprawl_density_threshold[                                  ;if density of a specific patch is greater than the threshold, we have to move them
      let turtles_in_patch turtles-on patches with [nID = ?]
      let number_turtles_in_patch count turtles_in_patch
      let sprawl_count round (sprawl_moving_rate * number_turtles_in_patch)       ; update the number of sprawled agents
      set sprawl_population sprawl_population + sprawl_count
      ;;; <<< start moving turtles >>> ;;;
      ask n-of sprawl_count turtles_in_patch[
        let turtle-saving housing
        let turtle-size [psize] of patch-here
        ; agents should move to a place that is vacant, its price is lower than their saving, it's less crowded, and the property size is greater than their current place

        let current-CR ([PR] of patch-here * exp (-0.04 * min (list 100 [p-age] of patch-here))) ; capping the age of a building to 100
        let current-price (price-change-by-density [density] of patch-here) * (current-CR * 12 * 32.02) ; more dense area have higher prices
        let current-nID [nID] of patch-here
        let target one-of patches with [occupied? = false and zID > 30 and price < (turtle-saving + current-price) and density < patch_density and psize > turtle-size]
        if target != nobody [
          ask patch-here [set occupied? false]
          move-to target
          let moved-price [price] of target
          ;if this patch is already developed by a developer, add the price to its saving
          ask patch-here [
            set occupied? true
            if pcolor != 3 [ask turtles with [color = pcolor] [set saving (saving + moved-price)]]
          ]
          set pID [ID] of patch-here
          ; selling price + agent's saving
          set housing (current-price + housing - moved-price) ;developer sell
          ; we need to set the pcolor of this house to 3 showing that an agent lives in this house and is not controlled by developers anymore
          set pcolor 3
        ]
      ]
    ]
  ]
end

to emigration
  let dying_count round (emigration_rate * count turtles with [zID > 30])     ;randomly remove agents from the model based on emigration-rate
  set emigration_population emigration_population + dying_count
  ask n-of dying_count turtles with [zID > 30] [
    ask patch-here [set occupied? false]
    die  ;RIP
  ]
end

to-report price-change-by-density [dens]     ;implement the "f(d) = 1+d" function
  report exp(1 + dens) ; exponential growth for the price according to density
end

; find the developer that is most frequent in a specific nID
to-report max-developer [current-nID]
  let dev-colors array:from-list (list yellow white violet gray orange)
  let yellow-patches count patches with [nID = current-nID and pcolor = yellow]
  let white-patches count patches with [nID = current-nID and pcolor = white]
  let violet-patches count patches with [nID = current-nID and pcolor = violet]
  let gray-patches count patches with [nID = current-nID and pcolor = gray]
  let orange-patches count patches with [nID = current-nID and pcolor = orange]
  let max-dev max (list yellow-patches white-patches violet-patches gray-patches orange-patches)
  let max-item-index position max-dev (list yellow-patches white-patches violet-patches gray-patches orange-patches)
  report array:item dev-colors max-item-index
end

to move-turtles                                      ;using Yang Zhou's segregation model
  ask turtles with [color = green or color = red or color = blue] [
    if happy? = false [
      let turtle-saving housing
      ; getting current price of the house based on property age (p-age), PR, CR
      let current-CR ([PR] of patch-here * exp (-0.04 * min (list 100 [p-age] of patch-here))) ; capping the age of a building to 100
      let current-price (price-change-by-density [density] of patch-here) * (current-CR * 12 * 32.02) ; more dense area have higher prices
      let current-nID [nID] of patch-here
      if near-CBD = 1 [
         ifelse low-rent = 1 [
            let target item 0 sort-on [price] patches with [occupied? = false and zID = 60]
            ; selling the property managed by current-price of the house added to the saving of the agent
            if target != nobody and [price] of target < (turtle-saving + current-price) [
               ; start buying
               ask patch-here [set occupied? false]
               move-to target
               let moved-price [price] of target
               ;if this patch is already developed by a developer, add the price to its saving
               ask patch-here [
                 set occupied? true
                 ; if the patch that agent is moving has already been developed, add the price to the saving of the developer
                 ; else add the price of the house to the most frequent developer in this nID
                 if pcolor != 3 [ask turtles with [color = pcolor] [set saving (saving + moved-price)]]
                 ;[ask turtles with [color = (max-developer current-nID)] [set saving (saving + moved-price)]]
               ]
               set pID [ID] of patch-here
               ; selling price + agent's saving
               set housing (current-price + housing - moved-price) ;developer sell
               ; we need to set the pcolor of this house to 3 showing that an agent lives in this house and is not controlled by developers anymore
               set pcolor 3
           ]
         ]
         [
          let target one-of patches with [occupied? = false and zID = 60 and price < turtle-saving + current-price ]
          if target != nobody [
            ask patch-here [set occupied? false]
            move-to target
            let moved-price [price] of target
            ;if this patch is already developed by a developer, add the price to its saving
            ask patch-here [
              set occupied? true
                 if pcolor != 3 [ask turtles with [color = pcolor] [set saving (saving + moved-price)]]
                 ;[ask turtles with [color = (max-developer current-nID)] [set saving (saving + moved-price)]]
            ]
            set pID [ID] of patch-here
            ; selling price + agent's saving
            set housing (current-price + housing - moved-price) ;developer sell
            set pcolor 3
          ]
        ]
      ]
      if near-CBD = 0 [
         ifelse low-rent = 1 [
            let target item 0 sort-on [price] patches with [occupied? = false and zID > 30]
            if target != nobody and [price] of target < turtle-saving + current-price [
               ; start buying
               ask patch-here [set occupied? false]
               move-to target
               let moved-price [price] of target
               ;if this patch is already developed by a developer, add the price to its saving
               ask patch-here [
                 set occupied? true
                 if pcolor != 3 [ask turtles with [color = pcolor] [set saving (saving + moved-price)]]
                 ;[ask turtles with [color = (max-developer current-nID)] [set saving (saving + moved-price)]]
               ]
               set pID [ID] of patch-here
               ; selling price + agent's saving
               set housing (current-price + housing - moved-price) ;developer sell
               set pcolor 3
           ]
         ]
         [
           let target one-of patches with [occupied? = false and zID > 30 and price < turtle-saving + current-price ]
           if target != nobody [
             ask patch-here [set occupied? false]
             move-to target
             let moved-price [price] of target
             ;if this patch is already developed by a developer, add the price to its saving
             ask patch-here [
               set occupied? true
                 if pcolor != 3 [ask turtles with [color = pcolor] [set saving (saving + moved-price)]]
                 ;[ask turtles with [color = (max-developer current-nID)] [set saving (saving + moved-price)]]
             ]
             set pID [ID] of patch-here
             ; selling price + agent's saving
             set housing (current-price + housing - moved-price) ;developer sell
             set pcolor 3
           ]
         ]
       ]
    ]
  ]
end

;;; update properties of each agent after one run
to update-turtles                                ;using Benenson's CA model, deciding based on economic status
  ask turtles [
    set saving (income - budget + saving)
    set housing (housing + budget * 0.28)
    ]       ;increasing the saving and housing every year
  ask turtles with [color = green or color = red or color = blue]
    [
      let current-pID pID
      let current-patch-nID [nID] of patch-here
      ;let num-neighbors count patches with [nID = current-patch-nID]
      let neighbors-in-nID patches with [nID = current-patch-nID]
      let num-neighbors count turtles-on neighbors-in-nID

      set similar-color count (turtles-on neighbors-in-nID)  with [ color = [ color ] of myself ]
      ;set similar-income count (turtles-on neighbors-in-nID) with [ income <= [lowerbound] of myself and income >= [upperbound] of myself and housing > 0]
      set similar-income count (turtles-on neighbors-in-nID) with [ ttype = [ttype] of myself and housing > 0]
      show (word "patch ID: " current-pID " patch nID: " current-patch-nID " num neighbors: " num-neighbors " similar-color: " similar-color " similar-income: " similar-income)
      set happy? (housing > 0) and (similar-color / num-neighbors > 0.5 or similar-income / num-neighbors > 0.5) ; happy if housing is greater than 0, meaning the agent is not under debt
    ]
end

;;; developers buy vacant places randomly based on their current saving
to developer-buy
  let vacant patches with [occupied? = false and zID > 30 and zID <= 90 and pcolor = 3 and p-age > 60]
  let sorted-vacant sort-on [(- Rent-gap)] vacant
  let developers turtles with [ttype = "dev"]
  foreach sorted-vacant[
    let vacant-price [price] of ?
    let vacant-id [ID] of ?
    let vacant-age [p-age] of ?
    let vacant-PR [PR] of ?
    let target one-of developers with [saving > vacant-price]
    if target != nobody[
      ask target[
        set saving saving - vacant-price
        let dv-color color
        ask one-of patches with [ID = vacant-id] [set pcolor dv-color
                                                  set p-age 0
                                                 ]
        set NOI NOI + ((vacant-PR * 12 * 32.02) * Cap-Rate / 100)   ; 32.02 is the price-to-rent ratio
      ]
    ]
  ]
end


;;;; <<< REPORTERS SECTION >>> ;;;;


to-report developer-reporter-white
  let list-white-saving []
  ask turtles with [color = white][set list-white-saving lput saving list-white-saving]
  set mean-white-saving mean list-white-saving
  report mean-white-saving
end
to-report developer-reporter-yellow
  let list-yellow-saving []
  ask turtles with [color = yellow][set list-yellow-saving lput saving list-yellow-saving]
  set mean-yellow-saving mean list-yellow-saving
  report mean-yellow-saving
end

to-report developer-reporter-orange
  let list-orange-saving []
  ask turtles with [color = orange][set list-orange-saving lput saving list-orange-saving]
  set mean-orange-saving mean list-orange-saving
  report mean-orange-saving
end

to-report developer-reporter-violet
  let list-violet-saving []
  ask turtles with [color = violet][set list-violet-saving lput saving list-violet-saving]
  set mean-violet-saving mean list-violet-saving
  report mean-violet-saving
end

to-report developer-reporter-gray
  let list-gray-saving []
  ask turtles with [color = gray][set list-gray-saving lput saving list-gray-saving]
  set mean-gray-saving mean list-gray-saving
  report mean-gray-saving
end

to-report nonprofessional-housing-reporter
  ;nonprofessional
  let list-nonprofessional-housing []
  ask turtles with [lowerbound = 31876 and upperbound = 53752][set list-nonprofessional-housing lput housing list-nonprofessional-housing]
  set mean-nonprofessional-housing mean list-nonprofessional-housing
  report mean-nonprofessional-housing
end

to-report professional-housing-reporter
  ;professional
  let list-professional-housing []
  ask turtles with [lowerbound = 117086 and upperbound = 158542][set list-professional-housing lput housing list-professional-housing]
  set mean-professional-housing mean list-professional-housing
  report mean-professional-housing
end

to-report professional-saving-reporter
  ;professional
  let list-professional-saving []
  ask turtles with [lowerbound = 117086 and upperbound = 158542][set list-professional-saving lput saving list-professional-saving]
  set mean-professional-saving mean list-professional-saving
  report mean-professional-saving
end

to-report nonprofessional-saving-reporter
  ;nonprofessional
  let list-nonprofessional-saving []
  ask turtles with [lowerbound = 31876 and upperbound = 53752][set list-nonprofessional-saving lput saving list-nonprofessional-saving]
  set mean-nonprofessional-saving mean list-nonprofessional-saving
  report mean-nonprofessional-saving
end

to-report innercity-professional-reporter
  set innercity-professional count turtles with [lowerbound = 117086 and upperbound = 158542 and zID = 60]
  report innercity-professional
end

to-report innercity-nonprofessional-reporter
  set innercity-nonprofessional count turtles with [lowerbound = 31876 and upperbound = 53752 and zID = 60]
  report innercity-nonprofessional
end

to-report suburbia-professional-reporter
  set suburbia-professional count turtles with [lowerbound = 117086 and upperbound = 158542 and zID = 90]
  report suburbia-professional
end

to-report suburbia-nonprofessional-reporter
  set suburbia-nonprofessional count turtles with [lowerbound = 31876 and upperbound = 53752 and zID = 90]
  report suburbia-nonprofessional
end

to-report white-developer-noi-reporter
  set white-noi sum [NOI] of turtles with [color = white]
  report white-noi
end

to-report yellow-developer-noi-reporter
  set yellow-noi sum [NOI] of turtles with [color = yellow]
  report yellow-noi
end

to-report orange-developer-noi-reporter
  set orange-noi sum [NOI] of turtles with [color = orange]
  report orange-noi
end

to-report violet-developer-noi-reporter
  set violet-noi sum [NOI] of turtles with [color = violet]
  report violet-noi
end

to-report gray-developer-noi-reporter
  set gray-noi sum [NOI] of turtles with [color = gray]
  report gray-noi
end

to-report ug-population-reporter
  set urban_growth_population 3 * count turtles with [color = green]
  report urban_growth_population
end

;to-report gentrified-population-reporter
 ; report gentrified_population
;end

to-report sprawl-population-reporter
  report sprawl_population
end

to-report emigration-population-reporter
  report emigration_population
end

to get-info
  ;developer saving

  let list-white-saving []
  let list-yellow-saving []
  let list-orange-saving []
  let list-violet-saving []
  let list-gray-saving []

  ask turtles with [color = white][set list-white-saving lput log saving 10 list-white-saving]
  ask turtles with [color = yellow][set list-yellow-saving lput log saving 10 list-yellow-saving]
  ask turtles with [color = orange][set list-orange-saving lput log saving 10 list-orange-saving]
  ask turtles with [color = violet][set list-violet-saving lput log saving 10 list-violet-saving]
  ask turtles with [color = gray][set list-gray-saving lput log saving 10 list-gray-saving]

  ;set mean-white-saving mean list-white-saving
  ;set mean-yellow-saving mean list-yellow-saving
  ;set mean-orange-saving mean list-orange-saving
  ;set mean-violet-saving mean list-violet-saving
  ;set mean-gray-saving mean list-gray-saving

  set mean-white-saving 0
  set mean-yellow-saving 0
  set mean-orange-saving 0
  set mean-violet-saving 0
  set mean-gray-saving 0

  ;professional

  let list-professional-saving []

  ask turtles with [lowerbound = 117086 and upperbound = 158542][set list-professional-saving lput saving list-professional-saving]

  set mean-professional-saving mean list-professional-saving

  ;nonprofessional

  let list-nonprofessional-saving []

  ask turtles with [lowerbound = 31876 and upperbound = 53752][set list-nonprofessional-saving lput saving list-nonprofessional-saving]

  set mean-nonprofessional-saving mean list-nonprofessional-saving

  ;number of professionals and nonprofessionals in inner city

  set innercity-professional count turtles with [lowerbound = 117086 and upperbound = 158542 and zID = 60]
  set innercity-nonprofessional count turtles with [lowerbound = 31876 and upperbound = 53752 and zID = 60]

  ;number of professionals and nonprofessionals in suburbia

  set suburbia-professional count turtles with [lowerbound = 117086 and upperbound = 158542 and zID = 90]
  set suburbia-nonprofessional count turtles with [lowerbound = 31876 and upperbound = 53752 and zID = 90]

  ;developer NOIs

  set white-noi sum [NOI] of turtles with [color = white]
  set yellow-noi sum [NOI] of turtles with [color = yellow]
  set orange-noi sum [NOI] of turtles with [color = orange]
  set violet-noi sum [NOI] of turtles with [color = violet]
  set gray-noi sum [NOI] of turtles with [color = gray]

  set urban_growth_population 3 * count turtles with [color = green]

end

to-report get-turtle-attributes ;turtle proc
  report (list ticks tID budget ttype income housing saving lowerbound upperbound happy? pID similar-color similar-income NOI near-CBD low-rent)
end

to-report get-patches-attributes ;turtle proc
  report (list ticks ID properties occupied? density zID nID p-age psize ptype price PR CR Rent-gap pcolor)
end

to export-turtles-vals ;turtle proc
  ask turtles [
    file-open "turtles.csv"
    file-print csv:to-row get-turtle-attributes
    file-close
  ]
end

to export-patches-vals ;turtle proc
  ;ask patches with [occupied? = true]
  ask patches [
    file-open "patches.csv"
    file-print csv:to-row get-patches-attributes
    file-close
  ]
end

to output [basepath]
  let interface-filename (word basepath "interface_ip-" initial_population "_ug-" ug_rate "_cr-" Cap-Rate "_gr-" gen_rate "_sdt-" sprawl_density_threshold "_smr-" sprawl_moving_rate "_sr-" emigration_rate "_" date-and-time ".png")
  let world-filename (word basepath "world_ip-" initial_population "_ug-" ug_rate "_cr-" Cap-Rate "_gr-" gen_rate "_sdt-" sprawl_density_threshold "_smr-" sprawl_moving_rate "_sr-" emigration_rate "_" date-and-time ".png")
  export-interface interface-filename
  export-view world-filename
end

to output-time [basepath tick-time]
  let interface-filename (word basepath "time_" tick-time "_interface_ip-" initial_population "_ug-" ug_rate "_cr-" Cap-Rate "_gr-" gen_rate "_sdt-" sprawl_density_threshold "_smr-" sprawl_moving_rate "_sr-" emigration_rate "_" date-and-time ".png")
  let world-filename (word basepath "time_" tick-time "_world_ip-" initial_population "_ug-" ug_rate "_cr-" Cap-Rate "_gr-" gen_rate "_sdt-" sprawl_density_threshold "_smr-" sprawl_moving_rate "_sr-" emigration_rate "_" date-and-time ".png")
  export-interface interface-filename
  export-view world-filename
end
@#$#@#$#@
GRAPHICS-WINDOW
209
10
621
443
100
100
2.0
1
10
1
1
1
0
1
1
1
-100
100
-100
100
0
0
1
ticks
30.0

BUTTON
14
30
78
63
Setup
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
100
32
163
65
Go
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
100
77
175
110
go once
go
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SLIDER
14
186
186
219
Cap-Rate
Cap-Rate
4.75
7.75
7.5
0.25
1
NIL
HORIZONTAL

MONITOR
15
125
147
170
Developed Properties
count patches with [pcolor = yellow or pcolor = orange or pcolor = violet or pcolor = gray or pcolor = white]
17
1
11

PLOT
646
10
1065
160
Developer Av. Saving
Years
Saving
0.0
30.0
0.0
10.0
true
true
"" ""
PENS
"White" 1.0 0 -16777216 true "" "plot mean-white-saving"
"Yellow" 1.0 0 -1184463 true "" "plot mean-yellow-saving"
"Orange" 1.0 0 -955883 true "" "plot mean-orange-saving"
"Violet" 1.0 0 -8630108 true "" "plot mean-violet-saving"
"Gray" 1.0 0 -7500403 true "" "plot mean-gray-saving"

PLOT
648
173
1066
323
P & NP Saving
Years
Saving
0.0
100.0
0.0
10.0
true
true
"" ""
PENS
"P" 1.0 0 -16777216 true "" "plot mean-professional-saving"
"NP" 1.0 0 -7500403 true "" "plot mean-nonprofessional-saving"

PLOT
1074
10
1493
160
Developer NOI
Years
NOI
0.0
30.0
0.0
10.0
true
true
"" ""
PENS
"White" 1.0 0 -16777216 true "" "plot white-noi"
"Yellow" 1.0 0 -1184463 true "" "plot yellow-noi"
"Orange" 1.0 0 -955883 true "" "plot orange-noi"
"Violet" 1.0 0 -8630108 true "" "plot violet-noi"
"Gray" 1.0 0 -7500403 true "" "plot gray-noi"

PLOT
1076
172
1492
322
Inner City P & NP
Years
People
0.0
10.0
0.0
10.0
true
true
"" ""
PENS
"P" 1.0 0 -16777216 true "" "plot innercity-professional"
"NP" 1.0 0 -7500403 true "" "plot innercity-nonprofessional"

PLOT
1078
335
1495
485
Suburbia P & NP
Years
People
0.0
30.0
0.0
10.0
true
true
"" ""
PENS
"P" 1.0 0 -16777216 true "" "plot suburbia-professional"
"NP" 1.0 0 -7500403 true "" "plot suburbia-nonprofessional"

SLIDER
15
233
187
266
ug_rate
ug_rate
0
1
0.17
0.1
1
NIL
HORIZONTAL

SLIDER
15
276
187
309
initial_population
initial_population
100
5000
1000
50
1
NIL
HORIZONTAL

SLIDER
15
317
187
350
gen_rate
gen_rate
0
1
0.26
0.1
1
NIL
HORIZONTAL

SLIDER
15
361
188
394
sprawl_density_threshold
sprawl_density_threshold
0
1
0.2
0.1
1
NIL
HORIZONTAL

SLIDER
17
404
189
437
sprawl_moving_rate
sprawl_moving_rate
0
1
0.1
0.1
1
NIL
HORIZONTAL

SLIDER
16
442
188
475
emigration_rate
emigration_rate
0
1
0.0050
0.001
1
NIL
HORIZONTAL

PLOT
649
333
1068
483
Population Over Time
Time
Population
0.0
600.0
0.0
9000.0
true
true
"" ""
PENS
"Growth" 1.0 0 -14439633 true "" "plot urban_growth_population"
"Sprawl" 1.0 0 -5298144 true "" "plot sprawl_population"
"Emigration" 1.0 0 -7500403 true "" "plot emigration_population"

@#$#@#$#@
## WHAT IS IT?

(a general understanding of what the model is trying to show or explain)

## HOW IT WORKS

(what rules the agents use to create the overall behavior of the model)

## HOW TO USE IT

(how to use the model, including a description of each of the items in the Interface tab)

## THINGS TO NOTICE

(suggested things for the user to notice while running the model)

## THINGS TO TRY

(suggested things for the user to try to do (move sliders, switches, etc.) with the model)

## EXTENDING THE MODEL

(suggested things to add or change in the Code tab to make the model more complicated, detailed, accurate, etc.)

## NETLOGO FEATURES

(interesting or unusual features of NetLogo that the model uses, particularly in the Code tab; or where workarounds were needed for missing features)

## RELATED MODELS

(models in the NetLogo Models Library and elsewhere which are of related interest)

## CREDITS AND REFERENCES

(a reference to the model's URL on the web if it has one, as well as any other necessary credits, citations, and links)
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270

@#$#@#$#@
NetLogo 5.2.1
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
<experiments>
  <experiment name="experiment" repetitions="1" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <final>output "/Users/yaserkeneshloo/Desktop/Niloofar/new-shrinkage/plots/default/"</final>
    <timeLimit steps="300"/>
    <metric>developer-reporter-white</metric>
    <metric>developer-reporter-yellow</metric>
    <metric>developer-reporter-orange</metric>
    <metric>developer-reporter-violet</metric>
    <metric>developer-reporter-gray</metric>
    <metric>nonprofessional-housing-reporter</metric>
    <metric>professional-housing-reporter</metric>
    <metric>professional-saving-reporter</metric>
    <metric>nonprofessional-saving-reporter</metric>
    <metric>innercity-professional-reporter</metric>
    <metric>innercity-nonprofessional-reporter</metric>
    <metric>suburbia-professional-reporter</metric>
    <metric>suburbia-nonprofessional-reporter</metric>
    <metric>white-developer-noi-reporter</metric>
    <metric>yellow-developer-noi-reporter</metric>
    <metric>orange-developer-noi-reporter</metric>
    <metric>violet-developer-noi-reporter</metric>
    <metric>gray-developer-noi-reporter</metric>
    <metric>ug-population-reporter</metric>
    <metric>gentrified-population-reporter</metric>
    <metric>sprawl-population-reporter</metric>
    <metric>shrinkage-population-reporter</metric>
    <enumeratedValueSet variable="shrinkage_rate">
      <value value="0.0050"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="gen_rate">
      <value value="0.26"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="Cap-Rate">
      <value value="7.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="ug_rate">
      <value value="0.17"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initial_population">
      <value value="300"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="sprawl_moving_rate">
      <value value="0.1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="sprawl_density_threshold">
      <value value="0.2"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="Gentrification by demand" repetitions="1" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <final>output "/Users/yaserkeneshloo/Desktop/Niloofar/new-shrinkage/plots/gentrification-by-demand/"</final>
    <timeLimit steps="300"/>
    <metric>developer-reporter-white</metric>
    <metric>developer-reporter-yellow</metric>
    <metric>developer-reporter-orange</metric>
    <metric>developer-reporter-violet</metric>
    <metric>developer-reporter-gray</metric>
    <metric>nonprofessional-housing-reporter</metric>
    <metric>professional-housing-reporter</metric>
    <metric>professional-saving-reporter</metric>
    <metric>nonprofessional-saving-reporter</metric>
    <metric>innercity-professional-reporter</metric>
    <metric>innercity-nonprofessional-reporter</metric>
    <metric>suburbia-professional-reporter</metric>
    <metric>suburbia-nonprofessional-reporter</metric>
    <metric>white-developer-noi-reporter</metric>
    <metric>yellow-developer-noi-reporter</metric>
    <metric>orange-developer-noi-reporter</metric>
    <metric>violet-developer-noi-reporter</metric>
    <metric>gray-developer-noi-reporter</metric>
    <metric>ug-population-reporter</metric>
    <metric>gentrified-population-reporter</metric>
    <metric>sprawl-population-reporter</metric>
    <metric>shrinkage-population-reporter</metric>
    <enumeratedValueSet variable="initial_population">
      <value value="100"/>
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="gen_rate">
      <value value="0.1"/>
      <value value="0.4"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="new" repetitions="1" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <final>output "/Users/niloofarjebelli/Desktop/plots/"</final>
    <timeLimit steps="10"/>
    <metric>developer-reporter-white</metric>
    <metric>developer-reporter-yellow</metric>
    <metric>developer-reporter-orange</metric>
    <metric>developer-reporter-violet</metric>
    <metric>developer-reporter-gray</metric>
    <metric>professional-saving-reporter</metric>
    <metric>nonprofessional-saving-reporter</metric>
    <metric>innercity-professional-reporter</metric>
    <metric>innercity-nonprofessional-reporter</metric>
    <metric>suburbia-professional-reporter</metric>
    <metric>suburbia-nonprofessional-reporter</metric>
    <metric>white-developer-noi-reporter</metric>
    <metric>yellow-developer-noi-reporter</metric>
    <metric>orange-developer-noi-reporter</metric>
    <metric>violet-developer-noi-reporter</metric>
    <metric>gray-developer-noi-reporter</metric>
    <metric>ug-population-reporter</metric>
    <enumeratedValueSet variable="initial_population">
      <value value="100"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="gen_rate">
      <value value="0.1"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="urbran sprawl" repetitions="1" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <final>output "/Users/yaserkeneshloo/Desktop/Niloofar/new-shrinkage/plots/urban-sprawl/"</final>
    <timeLimit steps="300"/>
    <metric>developer-reporter-white</metric>
    <metric>developer-reporter-yellow</metric>
    <metric>developer-reporter-orange</metric>
    <metric>developer-reporter-violet</metric>
    <metric>developer-reporter-gray</metric>
    <metric>professional-saving-reporter</metric>
    <metric>nonprofessional-saving-reporter</metric>
    <metric>innercity-professional-reporter</metric>
    <metric>innercity-nonprofessional-reporter</metric>
    <metric>suburbia-professional-reporter</metric>
    <metric>suburbia-nonprofessional-reporter</metric>
    <metric>white-developer-noi-reporter</metric>
    <metric>yellow-developer-noi-reporter</metric>
    <metric>orange-developer-noi-reporter</metric>
    <metric>violet-developer-noi-reporter</metric>
    <metric>gray-developer-noi-reporter</metric>
    <metric>ug-population-reporter</metric>
    <metric>gentrified-population-reporter</metric>
    <metric>sprawl-population-reporter</metric>
    <metric>shrinkage-population-reporter</metric>
    <enumeratedValueSet variable="initial_population">
      <value value="100"/>
      <value value="300"/>
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="sprawl_moving_rate">
      <value value="0.05"/>
      <value value="0.3"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="sprawl_density_threshold">
      <value value="0.05"/>
      <value value="0.5"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="shrinage" repetitions="1" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <final>output "/Users/yaserkeneshloo/Desktop/Niloofar/new-shrinkage/plots/shrinkage/"</final>
    <timeLimit steps="300"/>
    <metric>developer-reporter-white</metric>
    <metric>developer-reporter-yellow</metric>
    <metric>developer-reporter-orange</metric>
    <metric>developer-reporter-violet</metric>
    <metric>developer-reporter-gray</metric>
    <metric>professional-saving-reporter</metric>
    <metric>nonprofessional-saving-reporter</metric>
    <metric>nonprofessional-housing-reporter</metric>
    <metric>professional-housing-reporter</metric>
    <metric>innercity-professional-reporter</metric>
    <metric>innercity-nonprofessional-reporter</metric>
    <metric>suburbia-professional-reporter</metric>
    <metric>suburbia-nonprofessional-reporter</metric>
    <metric>white-developer-noi-reporter</metric>
    <metric>yellow-developer-noi-reporter</metric>
    <metric>orange-developer-noi-reporter</metric>
    <metric>violet-developer-noi-reporter</metric>
    <metric>gray-developer-noi-reporter</metric>
    <metric>ug-population-reporter</metric>
    <metric>gentrified-population-reporter</metric>
    <metric>sprawl-population-reporter</metric>
    <metric>shrinkage-population-reporter</metric>
    <enumeratedValueSet variable="initial_population">
      <value value="100"/>
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="shrinkage_rate">
      <value value="0.0010"/>
      <value value="0.01"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="growth" repetitions="1" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <final>output "/Users/yaserkeneshloo/Desktop/Niloofar/new/plots/growth/"</final>
    <timeLimit steps="300"/>
    <metric>developer-reporter-white</metric>
    <metric>developer-reporter-yellow</metric>
    <metric>developer-reporter-orange</metric>
    <metric>developer-reporter-violet</metric>
    <metric>developer-reporter-gray</metric>
    <metric>nonprofessional-housing-reporter</metric>
    <metric>professional-housing-reporter</metric>
    <metric>professional-saving-reporter</metric>
    <metric>nonprofessional-saving-reporter</metric>
    <metric>innercity-professional-reporter</metric>
    <metric>innercity-nonprofessional-reporter</metric>
    <metric>suburbia-professional-reporter</metric>
    <metric>suburbia-nonprofessional-reporter</metric>
    <metric>white-developer-noi-reporter</metric>
    <metric>yellow-developer-noi-reporter</metric>
    <metric>orange-developer-noi-reporter</metric>
    <metric>violet-developer-noi-reporter</metric>
    <metric>gray-developer-noi-reporter</metric>
    <metric>ug-population-reporter</metric>
    <metric>gentrified-population-reporter</metric>
    <metric>sprawl-population-reporter</metric>
    <metric>shrinkage-population-reporter</metric>
    <enumeratedValueSet variable="initial_population">
      <value value="100"/>
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="ug_rate">
      <value value="0.1"/>
      <value value="0.3"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="gentrification by supply" repetitions="1" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <final>output "/Users/yaserkeneshloo/Desktop/Niloofar/new/plots/gentrification-by-demand/"</final>
    <timeLimit steps="300"/>
    <metric>developer-reporter-white</metric>
    <metric>developer-reporter-yellow</metric>
    <metric>developer-reporter-orange</metric>
    <metric>developer-reporter-violet</metric>
    <metric>developer-reporter-gray</metric>
    <metric>nonprofessional-housing-reporter</metric>
    <metric>professional-housing-reporter</metric>
    <metric>professional-saving-reporter</metric>
    <metric>nonprofessional-saving-reporter</metric>
    <metric>innercity-professional-reporter</metric>
    <metric>innercity-nonprofessional-reporter</metric>
    <metric>suburbia-professional-reporter</metric>
    <metric>suburbia-nonprofessional-reporter</metric>
    <metric>white-developer-noi-reporter</metric>
    <metric>yellow-developer-noi-reporter</metric>
    <metric>orange-developer-noi-reporter</metric>
    <metric>violet-developer-noi-reporter</metric>
    <metric>gray-developer-noi-reporter</metric>
    <metric>ug-population-reporter</metric>
    <metric>gentrified-population-reporter</metric>
    <metric>sprawl-population-reporter</metric>
    <metric>shrinkage-population-reporter</metric>
    <enumeratedValueSet variable="initial_population">
      <value value="100"/>
      <value value="300"/>
      <value value="1000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="gen_rate">
      <value value="0.1"/>
      <value value="0.4"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="Cap-Rate">
      <value value="4.75"/>
      <value value="7.75"/>
    </enumeratedValueSet>
  </experiment>
</experiments>
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180

@#$#@#$#@
0
@#$#@#$#@
