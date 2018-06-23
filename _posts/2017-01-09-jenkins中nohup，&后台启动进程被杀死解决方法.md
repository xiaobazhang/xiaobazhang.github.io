---
layout: post
title: Jenkins解决后台启动自动被杀死方法
category: jekins
tags: jenkins java
date: 2017-01-09
author: suli
---

* content
{:toc}

## Jenkins持续集成系统
由于在公司负责了部门的docker虚拟化项目，所以要编译docker镜像，自己就搭建了一套jenkins持续集成系统，不仅可以用来编译docker镜像，同时可以用来给算法组和开发组日常编译使用。在部署程序的时候同时发现在nohup启动进程后，jenkins莫名阻塞在这里，同时子进程结束。第一直觉感觉好诡异，就开始找原因，发现了jenkins在编译结束后会默认会杀死脚本产生的子进程，有一下两种方法可以解决。








### 1. 重新设置环境变量build_id

在execute shell的输入框中加入BUILD_ID=DONTKILLME,即可防止jenkins杀死启动的衍生进程。

### 2，再启动jenkins的时候禁止jenkins杀死衍生进程

修改jenkins的/etc/sysconfig/jenkins配置，在JENKINS_JAVA_OPTIONS中加入-Dhudson.util.ProcessTree.disable=true。需要重启jenkins生效。此方法配置一次后，所有的job都无需设置BUILD_ID，就能够防止jenkins杀死启动的衍生进程。
