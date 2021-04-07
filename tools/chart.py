#!/usr/bin/python3
# Copyright 2020 HAProxy Technologies LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import argparse
import matplotlib
#matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np

#plt.style.use('ggplot')
#plt.rcParams['axes.facecolor']='white'
#plt.rcParams['savefig.facecolor']='white'

proxies = ['Envoy', 'HAProxy', 'NGINX Inc.', 'NGINX', 'Traefik']


def generate_single_bar(output, reqdata, title, ylabel, add_label=False):
    global proxies

    fig, ax = plt.subplots()
    x_pos = [i for i, _ in enumerate(proxies)]
    rects = plt.bar(x_pos, reqdata, color=['royalblue'])
    plt.xlabel("Proxy")
    plt.ylabel(ylabel)
    plt.title(title)
    plt.xticks(x_pos, proxies)
    if add_label:
        autolabel(ax, rects)
    plt.savefig(output)
#    plt.show()

def generate_grouped_bar(output, title, ylabel, bar1, bar2, bar3, add_label=False, percentiles=False):
    global proxies
    label1 = '75th'
    label2 = '95th'
    label3 = '99th'

    if not percentiles:
        label1 = '502'
        label2 = '503'
        label3 = '504'
    x = np.arange(len(proxies)) 
    width = 0.15 
    fig, ax = plt.subplots()
    rects1 = ax.bar(x, bar1, width, label=label1, color="royalblue")
    rects2 = ax.bar(x+width , bar2, width, label=label2, color="red")
    rects3 = ax.bar(x+(2 * width), bar3, width, label=label3, color="orange")
    ax.set_ylabel(ylabel)
    ax.set_title(title)
    ax.set_xticks(x)
    ax.set_xticklabels(proxies)
    ax.legend()
    if add_label:
        autolabel(ax, rects1) 
        autolabel(ax, rects2)
        autolabel(ax, rects3)
    fig.tight_layout()
    plt.savefig(output)
    #plt.show()

def generate2_grouped_bar(status502, status503, status504):
    global proxies
    x = np.arange(len(proxies))
    width = 0.15
    fig, ax = plt.subplots()
    rects1 = ax.bar(x, status502, width, label='502', color="royalblue")
    rects2 = ax.bar(x+width , status503, width, label='503', color="red")
    rects3 = ax.bar(x+(2 * width), status504, width, label='504', color="orange")
    ax.set_ylabel('Count')
    ax.set_title('Status code count')
    ax.set_xticks(x)
    ax.set_xticklabels(proxies)
    ax.legend()
    autolabel(ax, rects1)
    autolabel(ax, rects2)
    autolabel(ax, rects3)
    fig.tight_layout()
    plt.savefig(output)
    #plt.show()

def autolabel(ax, rects):
    """Attach a text label above each bar in *rects*, displaying its height."""
    for rect in rects:
        height = rect.get_height()
        if int(float('{}'.format(height))) > 0:
            ax.annotate('{}'.format(height),
                    xy=(rect.get_x() + rect.get_width() / 2, height),
                    xytext=(0, 3),  # 3 points vertical offset
                    textcoords="offset points",
                    ha='center', va='bottom')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("-c", "--chart", help="Type of chart to output", type=str, choices=["single","grouped"], required=True)
    parser.add_argument("-l", "--label", help="Print bar numbers", action="store_true")
    parser.add_argument("-o", "--output", help="Full path to file to output", type=str, required=True) 
    parser.add_argument("-p", "--percentile", help="Use Percentile labels", action="store_true")
    parser.add_argument("-s", "--single-data", help="Data to chart", nargs='+', type=float, required=False)
    parser.add_argument("-t", "--title", help="Title of chart", type=str, required=True)
    parser.add_argument("-y", "--ylabel", help="Description of y label", type=str, required=True)
    parser.add_argument("-bar1", "--bar1", help="Bar 1 data", nargs='+', type=float, required=False)
    parser.add_argument("-bar2", "--bar2", help="Bar 2 data", nargs='+', type=float, required=False)
    parser.add_argument("-bar3", "--bar3", help="Bar 3 data", nargs='+', type=float, required=False)
    args = parser.parse_args()

    if args.chart == "single":
        generate_single_bar(args.output, args.single_data, args.title, args.ylabel, args.label)
    elif args.chart == "grouped":
        generate_grouped_bar(args.output, args.title, args.ylabel, args.bar1, args.bar2, args.bar3, args.label, args.percentile)

if __name__ == "__main__":
   main()
