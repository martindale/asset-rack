
async = require 'async'
crypto = require 'crypto'
pathutil = require 'path'
mime = require 'mime'
{EventEmitter} = require 'events'

class exports.Asset extends EventEmitter
    defaultMaxAge: 60*60*24*365 # one year
    constructor: (options) ->
        options ?= {}
        @url = options.url if options.url?
        @contents = options.contents if options.contents?
        @ext = pathutil.extname @url
        @mimetype = options.mimetype if options.mimetype?
        @mimetype ?= mime.types[@ext.slice(1, @ext.length)]
        @mimetype ?= 'text/plain'
        @hash = options.hash
        @maxAge = options.maxAge
        @allowNoHashCache = options.allowNoHashCache
        @on 'newListener', (event, listener) =>
            if event is 'complete' and @completed is true
                listener()
        @on 'created', (data) =>
            if data?.contents?
                @contents = data.contents
            if data?.assets?
                @assets = data.assets
            if @contents?
                @createSpecificUrl()
            @completed = true
            @emit 'complete'
        @on 'error', (error) =>
            throw error if @listeners 'error' is 1
        @on 'start', =>
            @maxAge ?= @rack?.maxAge
            @maxAge ?= @defaultMaxAge
            @allowNoHashCache ?= @rack?.allowNoHashCache
            @create options
        super()
        process.nextTick =>
            @maxAge ?= @defaultMaxAge
            return @create options unless @rack?

    respond: (request, response) ->
        response.header 'Content-Type', @mimetype
        useCache =  @maxAge? and (request.url isnt @url or @allowNoHashCache is true)
        if useCache
            response.header 'Cache-Control', "public, max-age=#{@maxAge}"
        #response.header 'Content-Length', @contents.length
        for key, value of @headers
            response.header key, value
        return response.send @contents
        
    checkUrl: (url) ->
        url is @specificUrl or (not @hash? and url is @url)

    handle: (request, response, next) ->
        handle = =>
            if @assets?
                for asset in @assets
                    if asset.checkUrl request.url
                        return asset.respond request, response
            if @checkUrl(request.url)
                @respond request, response
            else next()
        if @completed is true
            handle()
        else @on 'complete', ->
            handle()
        
    create: (options) ->
        @emit 'created'

    tag: ->
        switch @mimetype
            when 'text/javascript'
                tag = "\n<script type=\"#{@mimetype}\" "
                return tag += "src=\"#{@specificUrl}\"></script>"
            when 'text/css'
                return "\n<link rel=\"stylesheet\" href=\"#{@specificUrl}\">"

    createSpecificUrl: ->
        @md5 = crypto.createHash('md5').update(@contents).digest 'hex'
        if @hash is false
            @useDefaultMaxAge = false
            return @specificUrl = @url
        @specificUrl = "#{@url.slice(0, @url.length - @ext.length)}-#{@md5}#{@ext}"
        if @hostname?
            @specificUrl = "//#{@hostname}#{@specificUrl}"
        
    isRelevantUrl: (specificUrl) ->
        baseUrl = @url.slice(0, @url.length - @ext.length)
        if specificUrl.indexOf baseUrl isnt -1 and @ext is pathutil.extname specificUrl
            return true
        return false