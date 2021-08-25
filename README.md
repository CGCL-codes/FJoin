# FJoin: an FPGA-based parallel accelerator for stream join

FJoin is an FPGA-based parallel accelerator for stream which leverages a large number of basic join units connected in series to form a deep join pipeline to achieve large-scale parallelism.FJoin can do High-Parallel Flow Join, in which data of the join window can flow through once to complete all join calculations after loading multiple stream tuples. The host CPU and FPGA device coordinate control, divide the continuous stream join calculation into independent small-batch tasks and efficiently ensure completeness of parallel stream join.  FJoin is implemented on a platform equipped with an FPGA accelerator card.The test results based on large-scale real data sets show that FJoin can increase the join calculation speed by 16 times using a single FPGA accelerator card and reach 5 times system throughput compared with the current best stream join system deployed on a 40-node cluster, and latency meets the real-time stream processing requirements.

# Introduction

# FJoin architecture

# Basic join unit

# How to use?

# Evaluation Result
![image]（FJoin/images/FJoin_img_evaluation1.png）
![image]（FJoin/images/FJoin_img_evaluation2.png）
# Publication
If you want to know more detailed information, please refer to this paper:  
The paper is being reviewed by Sci Sin Inform.

# Authors and Copyright
FJoin is developed in National Engineering Research Center for Big Data Technology and System, Cluster and Grid Computing Lab, Services Computing Technology and System Lab, School of Computer Science and Technology, Huazhong University of Science and Technology, Wuhan, China by Litao Lin (litaolin@hust.edu.cn), Hanhua Chen (chen@hust.edu.cn), Hai Jin (hjin@hust.edu.cn).

Copyright (C) 2021, [STCS & CGCL](http://grid.hust.edu.cn/) and [Huazhong University of Science and Technology](https://www.hust.edu.cn/).
