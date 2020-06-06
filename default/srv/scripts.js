/*!
 * Virtualmin Landing v1.0.2
 * Copyright 2020 Virtualmin, Inc.
 * Copyright 2020 Ilia Rostovtsev
 * Licensed under MIT
 */

/* jshint strict: true */
/* jshint esversion: 6 */

'use strict';

const init = function() {
    let query = (() => {
            let params = {};
            (new URLSearchParams(document.location.search)).forEach((d, e) => {
                let a = decodeURIComponent(e),
                    c = decodeURIComponent(d)
                if (a.endsWith("[]")) {
                    a = a.replace("[]", ""), params[a] || (params[a] = []), params[a].push(c)
                } else {
                    let b = a.match(/\[([a-z0-9_\/\s,.-])+\]$/g)
                    b ? (a = a.replace(b, ""), b = b[0].replace("[", "").replace("]", ""), params[a] || (params[a] = []), params[a][b] = c) : params[a] = c
                }
            })
            return params
        })(),
        origin = window.location.origin,
        bodyClassList = document.querySelector('body').classList,
        datatime = new Date(),
        hour = datatime.getHours(),
        day = hour < 21 && hour >= 8 ? 1 : 0;
    if (origin && origin.includes('//') || query.domain) {
        origin = origin.split('//')[1]
        document.querySelector('.domain').innerText = query.domain || origin;
    }
    if (query.theme) {
        bodyClassList.remove('dark');
        bodyClassList.add(query.theme);
    } else if (day) {
        bodyClassList.remove('dark');
        bodyClassList.add('white');
    }
    if (query.title) {
        document.querySelector('.default-title').innerText = query.title;
    }
    if (query.message) {
        document.querySelector('.message').innerText = query.message;
    }
    if (query.error) {
        let error = document.querySelector('.error'),
            error_message_link = document.querySelector('.error-message').querySelector('a');
        error.innerText = query.error;
        error_message_link.href = error_message_link.href.replace('$1', query.error);
    }
    document.querySelector('.veil-vm.bg').style.backgroundImage = "url('srv/images/bg-" + Math.floor(Math.random() * Math.floor(4)) + ".jpg')";
}