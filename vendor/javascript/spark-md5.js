// spark-md5@3.0.2 downloaded from https://ga.jspm.io/npm:spark-md5@3.0.2/spark-md5.js

var r="undefined"!==typeof globalThis?globalThis:"undefined"!==typeof self?self:global;var t={};(function(r){t=r()})((function(t){var e=["0","1","2","3","4","5","6","7","8","9","a","b","c","d","e","f"];function md5cycle(r,t){var e=r[0],n=r[1],a=r[2],f=r[3];e+=(n&a|~n&f)+t[0]-680876936|0;e=(e<<7|e>>>25)+n|0;f+=(e&n|~e&a)+t[1]-389564586|0;f=(f<<12|f>>>20)+e|0;a+=(f&e|~f&n)+t[2]+606105819|0;a=(a<<17|a>>>15)+f|0;n+=(a&f|~a&e)+t[3]-1044525330|0;n=(n<<22|n>>>10)+a|0;e+=(n&a|~n&f)+t[4]-176418897|0;e=(e<<7|e>>>25)+n|0;f+=(e&n|~e&a)+t[5]+1200080426|0;f=(f<<12|f>>>20)+e|0;a+=(f&e|~f&n)+t[6]-1473231341|0;a=(a<<17|a>>>15)+f|0;n+=(a&f|~a&e)+t[7]-45705983|0;n=(n<<22|n>>>10)+a|0;e+=(n&a|~n&f)+t[8]+1770035416|0;e=(e<<7|e>>>25)+n|0;f+=(e&n|~e&a)+t[9]-1958414417|0;f=(f<<12|f>>>20)+e|0;a+=(f&e|~f&n)+t[10]-42063|0;a=(a<<17|a>>>15)+f|0;n+=(a&f|~a&e)+t[11]-1990404162|0;n=(n<<22|n>>>10)+a|0;e+=(n&a|~n&f)+t[12]+1804603682|0;e=(e<<7|e>>>25)+n|0;f+=(e&n|~e&a)+t[13]-40341101|0;f=(f<<12|f>>>20)+e|0;a+=(f&e|~f&n)+t[14]-1502002290|0;a=(a<<17|a>>>15)+f|0;n+=(a&f|~a&e)+t[15]+1236535329|0;n=(n<<22|n>>>10)+a|0;e+=(n&f|a&~f)+t[1]-165796510|0;e=(e<<5|e>>>27)+n|0;f+=(e&a|n&~a)+t[6]-1069501632|0;f=(f<<9|f>>>23)+e|0;a+=(f&n|e&~n)+t[11]+643717713|0;a=(a<<14|a>>>18)+f|0;n+=(a&e|f&~e)+t[0]-373897302|0;n=(n<<20|n>>>12)+a|0;e+=(n&f|a&~f)+t[5]-701558691|0;e=(e<<5|e>>>27)+n|0;f+=(e&a|n&~a)+t[10]+38016083|0;f=(f<<9|f>>>23)+e|0;a+=(f&n|e&~n)+t[15]-660478335|0;a=(a<<14|a>>>18)+f|0;n+=(a&e|f&~e)+t[4]-405537848|0;n=(n<<20|n>>>12)+a|0;e+=(n&f|a&~f)+t[9]+568446438|0;e=(e<<5|e>>>27)+n|0;f+=(e&a|n&~a)+t[14]-1019803690|0;f=(f<<9|f>>>23)+e|0;a+=(f&n|e&~n)+t[3]-187363961|0;a=(a<<14|a>>>18)+f|0;n+=(a&e|f&~e)+t[8]+1163531501|0;n=(n<<20|n>>>12)+a|0;e+=(n&f|a&~f)+t[13]-1444681467|0;e=(e<<5|e>>>27)+n|0;f+=(e&a|n&~a)+t[2]-51403784|0;f=(f<<9|f>>>23)+e|0;a+=(f&n|e&~n)+t[7]+1735328473|0;a=(a<<14|a>>>18)+f|0;n+=(a&e|f&~e)+t[12]-1926607734|0;n=(n<<20|n>>>12)+a|0;e+=(n^a^f)+t[5]-378558|0;e=(e<<4|e>>>28)+n|0;f+=(e^n^a)+t[8]-2022574463|0;f=(f<<11|f>>>21)+e|0;a+=(f^e^n)+t[11]+1839030562|0;a=(a<<16|a>>>16)+f|0;n+=(a^f^e)+t[14]-35309556|0;n=(n<<23|n>>>9)+a|0;e+=(n^a^f)+t[1]-1530992060|0;e=(e<<4|e>>>28)+n|0;f+=(e^n^a)+t[4]+1272893353|0;f=(f<<11|f>>>21)+e|0;a+=(f^e^n)+t[7]-155497632|0;a=(a<<16|a>>>16)+f|0;n+=(a^f^e)+t[10]-1094730640|0;n=(n<<23|n>>>9)+a|0;e+=(n^a^f)+t[13]+681279174|0;e=(e<<4|e>>>28)+n|0;f+=(e^n^a)+t[0]-358537222|0;f=(f<<11|f>>>21)+e|0;a+=(f^e^n)+t[3]-722521979|0;a=(a<<16|a>>>16)+f|0;n+=(a^f^e)+t[6]+76029189|0;n=(n<<23|n>>>9)+a|0;e+=(n^a^f)+t[9]-640364487|0;e=(e<<4|e>>>28)+n|0;f+=(e^n^a)+t[12]-421815835|0;f=(f<<11|f>>>21)+e|0;a+=(f^e^n)+t[15]+530742520|0;a=(a<<16|a>>>16)+f|0;n+=(a^f^e)+t[2]-995338651|0;n=(n<<23|n>>>9)+a|0;e+=(a^(n|~f))+t[0]-198630844|0;e=(e<<6|e>>>26)+n|0;f+=(n^(e|~a))+t[7]+1126891415|0;f=(f<<10|f>>>22)+e|0;a+=(e^(f|~n))+t[14]-1416354905|0;a=(a<<15|a>>>17)+f|0;n+=(f^(a|~e))+t[5]-57434055|0;n=(n<<21|n>>>11)+a|0;e+=(a^(n|~f))+t[12]+1700485571|0;e=(e<<6|e>>>26)+n|0;f+=(n^(e|~a))+t[3]-1894986606|0;f=(f<<10|f>>>22)+e|0;a+=(e^(f|~n))+t[10]-1051523|0;a=(a<<15|a>>>17)+f|0;n+=(f^(a|~e))+t[1]-2054922799|0;n=(n<<21|n>>>11)+a|0;e+=(a^(n|~f))+t[8]+1873313359|0;e=(e<<6|e>>>26)+n|0;f+=(n^(e|~a))+t[15]-30611744|0;f=(f<<10|f>>>22)+e|0;a+=(e^(f|~n))+t[6]-1560198380|0;a=(a<<15|a>>>17)+f|0;n+=(f^(a|~e))+t[13]+1309151649|0;n=(n<<21|n>>>11)+a|0;e+=(a^(n|~f))+t[4]-145523070|0;e=(e<<6|e>>>26)+n|0;f+=(n^(e|~a))+t[11]-1120210379|0;f=(f<<10|f>>>22)+e|0;a+=(e^(f|~n))+t[2]+718787259|0;a=(a<<15|a>>>17)+f|0;n+=(f^(a|~e))+t[9]-343485551|0;n=(n<<21|n>>>11)+a|0;r[0]=e+r[0]|0;r[1]=n+r[1]|0;r[2]=a+r[2]|0;r[3]=f+r[3]|0}function md5blk(r){var t,e=[];for(t=0;t<64;t+=4)e[t>>2]=r.charCodeAt(t)+(r.charCodeAt(t+1)<<8)+(r.charCodeAt(t+2)<<16)+(r.charCodeAt(t+3)<<24);return e}function md5blk_array(r){var t,e=[];for(t=0;t<64;t+=4)e[t>>2]=r[t]+(r[t+1]<<8)+(r[t+2]<<16)+(r[t+3]<<24);return e}function md51(r){var t,e,n,a,f,h,i=r.length,o=[1732584193,-271733879,-1732584194,271733878];for(t=64;t<=i;t+=64)md5cycle(o,md5blk(r.substring(t-64,t)));r=r.substring(t-64);e=r.length;n=[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0];for(t=0;t<e;t+=1)n[t>>2]|=r.charCodeAt(t)<<(t%4<<3);n[t>>2]|=128<<(t%4<<3);if(t>55){md5cycle(o,n);for(t=0;t<16;t+=1)n[t]=0}a=8*i;a=a.toString(16).match(/(.*?)(.{0,8})$/);f=parseInt(a[2],16);h=parseInt(a[1],16)||0;n[14]=f;n[15]=h;md5cycle(o,n);return o}function md51_array(r){var t,e,n,a,f,h,i=r.length,o=[1732584193,-271733879,-1732584194,271733878];for(t=64;t<=i;t+=64)md5cycle(o,md5blk_array(r.subarray(t-64,t)));r=t-64<i?r.subarray(t-64):new Uint8Array(0);e=r.length;n=[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0];for(t=0;t<e;t+=1)n[t>>2]|=r[t]<<(t%4<<3);n[t>>2]|=128<<(t%4<<3);if(t>55){md5cycle(o,n);for(t=0;t<16;t+=1)n[t]=0}a=8*i;a=a.toString(16).match(/(.*?)(.{0,8})$/);f=parseInt(a[2],16);h=parseInt(a[1],16)||0;n[14]=f;n[15]=h;md5cycle(o,n);return o}function rhex(r){var t,n="";for(t=0;t<4;t+=1)n+=e[r>>8*t+4&15]+e[r>>8*t&15];return n}function hex(r){var t;for(t=0;t<r.length;t+=1)r[t]=rhex(r[t]);return r.join("")}"5d41402abc4b2a76b9719d911017c592"!==hex(md51("hello"))&&function(r,t){var e=(65535&r)+(65535&t),n=(r>>16)+(t>>16)+(e>>16);return n<<16|65535&e};"undefined"===typeof ArrayBuffer||ArrayBuffer.prototype.slice||function(){function clamp(r,t){r=0|r||0;return r<0?Math.max(r+t,0):Math.min(r,t)}ArrayBuffer.prototype.slice=function(e,n){var a,f,h,i,o=(this||r).byteLength,u=clamp(e,o),s=o;n!==t&&(s=clamp(n,o));if(u>s)return new ArrayBuffer(0);a=s-u;f=new ArrayBuffer(a);h=new Uint8Array(f);i=new Uint8Array(this||r,u,a);h.set(i);return f}}();function toUtf8(r){/[\u0080-\uFFFF]/.test(r)&&(r=unescape(encodeURIComponent(r)));return r}function utf8Str2ArrayBuffer(r,t){var e,n=r.length,a=new ArrayBuffer(n),f=new Uint8Array(a);for(e=0;e<n;e+=1)f[e]=r.charCodeAt(e);return t?f:a}function arrayBuffer2Utf8Str(r){return String.fromCharCode.apply(null,new Uint8Array(r))}function concatenateArrayBuffers(r,t,e){var n=new Uint8Array(r.byteLength+t.byteLength);n.set(new Uint8Array(r));n.set(new Uint8Array(t),r.byteLength);return e?n:n.buffer}function hexToBinaryString(r){var t,e=[],n=r.length;for(t=0;t<n-1;t+=2)e.push(parseInt(r.substr(t,2),16));return String.fromCharCode.apply(String,e)}function SparkMD5(){this.reset()}
/**
   * Appends a string.
   * A conversion will be applied if an utf8 string is detected.
   *
   * @param {String} str The string to be appended
   *
   * @return {SparkMD5} The instance itself
   */SparkMD5.prototype.append=function(t){this.appendBinary(toUtf8(t));return this||r};
/**
   * Appends a binary string.
   *
   * @param {String} contents The binary string to be appended
   *
   * @return {SparkMD5} The instance itself
   */SparkMD5.prototype.appendBinary=function(t){(this||r)._buff+=t;(this||r)._length+=t.length;var e,n=(this||r)._buff.length;for(e=64;e<=n;e+=64)md5cycle((this||r)._hash,md5blk((this||r)._buff.substring(e-64,e)));(this||r)._buff=(this||r)._buff.substring(e-64);return this||r};
/**
   * Finishes the incremental computation, reseting the internal state and
   * returning the result.
   *
   * @param {Boolean} raw True to get the raw string, false to get the hex string
   *
   * @return {String} The result
   */SparkMD5.prototype.end=function(t){var e,n,a=(this||r)._buff,f=a.length,h=[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0];for(e=0;e<f;e+=1)h[e>>2]|=a.charCodeAt(e)<<(e%4<<3);this._finish(h,f);n=hex((this||r)._hash);t&&(n=hexToBinaryString(n));this.reset();return n};SparkMD5.prototype.reset=function(){(this||r)._buff="";(this||r)._length=0;(this||r)._hash=[1732584193,-271733879,-1732584194,271733878];return this||r};SparkMD5.prototype.getState=function(){return{buff:(this||r)._buff,length:(this||r)._length,hash:(this||r)._hash.slice()}};
/**
   * Gets the internal state of the computation.
   *
   * @param {Object} state The state
   *
   * @return {SparkMD5} The instance itself
   */SparkMD5.prototype.setState=function(t){(this||r)._buff=t.buff;(this||r)._length=t.length;(this||r)._hash=t.hash;return this||r};SparkMD5.prototype.destroy=function(){delete(this||r)._hash;delete(this||r)._buff;delete(this||r)._length};
/**
   * Finish the final calculation based on the tail.
   *
   * @param {Array}  tail   The tail (will be modified)
   * @param {Number} length The length of the remaining buffer
   */SparkMD5.prototype._finish=function(t,e){var n,a,f,h=e;t[h>>2]|=128<<(h%4<<3);if(h>55){md5cycle((this||r)._hash,t);for(h=0;h<16;h+=1)t[h]=0}n=8*(this||r)._length;n=n.toString(16).match(/(.*?)(.{0,8})$/);a=parseInt(n[2],16);f=parseInt(n[1],16)||0;t[14]=a;t[15]=f;md5cycle((this||r)._hash,t)};
/**
   * Performs the md5 hash on a string.
   * A conversion will be applied if utf8 string is detected.
   *
   * @param {String}  str The string
   * @param {Boolean} [raw] True to get the raw string, false to get the hex string
   *
   * @return {String} The result
   */SparkMD5.hash=function(r,t){return SparkMD5.hashBinary(toUtf8(r),t)};
/**
   * Performs the md5 hash on a binary string.
   *
   * @param {String}  content The binary string
   * @param {Boolean} [raw]     True to get the raw string, false to get the hex string
   *
   * @return {String} The result
   */SparkMD5.hashBinary=function(r,t){var e=md51(r),n=hex(e);return t?hexToBinaryString(n):n};SparkMD5.ArrayBuffer=function(){this.reset()};
/**
   * Appends an array buffer.
   *
   * @param {ArrayBuffer} arr The array to be appended
   *
   * @return {SparkMD5.ArrayBuffer} The instance itself
   */SparkMD5.ArrayBuffer.prototype.append=function(t){var e,n=concatenateArrayBuffers((this||r)._buff.buffer,t,true),a=n.length;(this||r)._length+=t.byteLength;for(e=64;e<=a;e+=64)md5cycle((this||r)._hash,md5blk_array(n.subarray(e-64,e)));(this||r)._buff=e-64<a?new Uint8Array(n.buffer.slice(e-64)):new Uint8Array(0);return this||r};
/**
   * Finishes the incremental computation, reseting the internal state and
   * returning the result.
   *
   * @param {Boolean} raw True to get the raw string, false to get the hex string
   *
   * @return {String} The result
   */SparkMD5.ArrayBuffer.prototype.end=function(t){var e,n,a=(this||r)._buff,f=a.length,h=[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0];for(e=0;e<f;e+=1)h[e>>2]|=a[e]<<(e%4<<3);this._finish(h,f);n=hex((this||r)._hash);t&&(n=hexToBinaryString(n));this.reset();return n};SparkMD5.ArrayBuffer.prototype.reset=function(){(this||r)._buff=new Uint8Array(0);(this||r)._length=0;(this||r)._hash=[1732584193,-271733879,-1732584194,271733878];return this||r};SparkMD5.ArrayBuffer.prototype.getState=function(){var t=SparkMD5.prototype.getState.call(this||r);t.buff=arrayBuffer2Utf8Str(t.buff);return t};
/**
   * Gets the internal state of the computation.
   *
   * @param {Object} state The state
   *
   * @return {SparkMD5.ArrayBuffer} The instance itself
   */SparkMD5.ArrayBuffer.prototype.setState=function(t){t.buff=utf8Str2ArrayBuffer(t.buff,true);return SparkMD5.prototype.setState.call(this||r,t)};SparkMD5.ArrayBuffer.prototype.destroy=SparkMD5.prototype.destroy;SparkMD5.ArrayBuffer.prototype._finish=SparkMD5.prototype._finish;
/**
   * Performs the md5 hash on an array buffer.
   *
   * @param {ArrayBuffer} arr The array buffer
   * @param {Boolean}     [raw] True to get the raw string, false to get the hex one
   *
   * @return {String} The result
   */SparkMD5.ArrayBuffer.hash=function(r,t){var e=md51_array(new Uint8Array(r)),n=hex(e);return t?hexToBinaryString(n):n};return SparkMD5}));var e=t;export default e;

