###
Crafting Guide - item_page_controller.coffee

Copyright (c) 2015 by Redwood Labs
All rights reserved.
###

_                          = require 'underscore'
AdsenseController          = require './adsense_controller'
{Duration}                 = require '../constants'
EditableFile               = require '../models/editable_file'
{Event}                    = require '../constants'
FullRecipeController       = require './full_recipe_controller'
{GitHub}                   = require '../constants'
ImageLoader                = require './image_loader'
Item                       = require '../models/item'
ItemGroupController        = require './item_group_controller'
ItemPage                   = require '../models/item_page'
ItemSlug                   = require '../models/item_slug'
MarkdownSectionController  = require './markdown_section_controller'
MultiblockViewerController = require './multiblock_viewer_controller'
PageController             = require './page_controller'
{Text}                     = require '../constants'
{Url}                      = require '../constants'
VideoController            = require './video_controller'
w                          = require 'when'

########################################################################################################################

module.exports = class ItemPageController extends PageController

    FILE_UPLOAD_DELAY = 250

    constructor: (options={})->
        if not options.client? then throw new Error 'options.client is required'
        if not options.itemSlug? then throw new Error 'options.itemSlug is required'
        if not options.imageLoader? then throw new Error 'options.imageLoader is required'
        if not options.modPack? then throw new Error 'options.modPack is required'

        options.model        ?= new ItemPage modPack:options.modPack
        options.templateName ?= 'item_page'

        super options

        @client      = options.client
        @imageLoader = options.imageLoader
        @modPack     = options.modPack

        @_descriptionFile = null
        @_itemSlug    = options.itemSlug

        @modPack.on Event.change, => @tryRefresh()

    # Event Methods ################################################################################

    craftingPlanButtonClicked: ->
        display = @modPack.findItemDisplay @model.item.slug
        router.navigate display.craftingUrl, trigger:true
        return false

    # PageController Overrides #####################################################################

    getMetaDescription: ->
        if @model.item?
            display = @modPack.findItemDisplay @model.item.slug
            return Text.itemDescription display
        else
            return null

    getTitle: ->
        return unless @model.item?
        display = @modPack.findItemDisplay @model.item.slug
        return "#{display.itemName} from #{display.modName}"

    # BaseController Overrides #####################################################################

    onDidRender: ->
        @adsenseController = @addChild AdsenseController, '.view__adsense', model:'sidebar_skyscraper'

        options                      = imageLoader:@imageLoader, modPack:@modPack, show:false
        @_multiblockController       = @addChild MultiblockViewerController, '.view__multiblock_viewer', options
        @_similarItemsController     = @addChild ItemGroupController, '.view__item_group.similar', options
        @_usedAsToolToMakeController = @addChild ItemGroupController, '.view__item_group.usedAsToolToMake', options
        @_usedToMakeController       = @addChild ItemGroupController, '.view__item_group.usedToMake', options

        @_descriptionController = @addChild MarkdownSectionController, '.section.description',
            client:       @client
            editable:     true
            modPack:      @modPack
            beginEditing: => @_beginEditingDescription()
            endEditing:   => @_endEditingDescription()

        @$byline                  = @$('.byline')
        @$bylineLink              = @$('.byline a')
        @$descriptionSection      = @$('.description')
        @$multiblockSection       = @$('.multiblock.section')
        @$name                    = @$('h1.name')
        @$officialPageLink        = @$('a.officialPage')
        @$recipeContainer         = @$('.recipes .panel')
        @$recipesSection          = @$('.recipes')
        @$recipesSectionTitle     = @$('.recipes h2')
        @$similarSection          = @$('.similar')
        @$titleImage              = @$('.titleImage img')
        @$usedAsToolToMakeSection = @$('.usedAsToolToMake')
        @$usedToMakeSection       = @$('.usedToMake')
        @$videosContainer         = @$('.videos .panel')
        @$videosSection           = @$('.videos')
        @$videosSectionTitle      = @$('.videos h2')
        super

    refresh: ->
        @_resolveItemSlug()

        if @model.item?
            display = @modPack.findItemDisplay @model.item.slug
            @imageLoader.load display.iconUrl, @$titleImage
            @$name.html display.itemName

            @_descriptionController.imageBase = Url.itemImageDir display

            if @model.item.officialUrl?
                @$officialPageLink.attr 'href', @model.item.officialUrl
                @show @$officialPageLink
            else
                @hide @$officialPageLink

            @show()
        else
            @hide()

        @_refreshByline()
        @_refreshDescription()
        @_refreshMultiblock()
        @_refreshRecipes()
        @_refreshSimilarItems()
        @_refreshUsedAsToolToMake()
        @_refreshUsedToMake()
        @_refreshVideos()

        super

    setUser: (user)->
        super user
        @_descriptionController.user = user if @_descriptionController?

    # Backbone.View Overrides ######################################################################

    events: ->
        return _.extend super,
            'click a.craftingPlan':      'routeLinkClick'
            'click .byline a':           'routeLinkClick'
            'click .markdown a':         'routeLinkClick'
            'click button.craftingPlan': 'craftingPlanButtonClicked'

    # Private Methods ##############################################################################

    _beginEditingDescription: ->
        if not global.router.user?
            global.router.login()
            return w.reject new Error 'must be logged in to edit'

        if not @model.item?
            return w.reject new Error 'must have an item'

        pathArgs = modSlug:@_itemSlug.mod, itemSlug:@_itemSlug.item
        attributes =
            fileName: GitHub.file.itemDescription.fileName pathArgs
            path:     GitHub.file.itemDescription.path pathArgs

        @_descriptionFile = new EditableFile attributes, client:@client
        @_descriptionFile.fetch()
            .then =>
                if @_descriptionFile.encodedData?.length > 0
                    @model.item.parse @_descriptionFile.getDecodedData 'utf8'
                else
                    @model.item.description = ''

                @_descriptionController.model = @model.item.description

    _endEditingDescription: ->
        oldDescription = @model.item.description
        promises = []

        saveList = []
        for imageFile in @_descriptionController.imageFiles
            saveList.push
                file:    imageFile
                message: "User-submitted image for #{@model.item.name} from #{global.hostName}"

        @model.item.description = @_descriptionController.model
        @_descriptionFile.setDecodedData @model.item.unparse()
        saveList.push
            file:    @_descriptionFile
            message: "User-submitted text for #{@model.item.name} from #{global.hostName}"

        saveNextFile = (fileList)->
            return w(true) if fileList.length is 0
            {file, message} = fileList.shift()
            file.save message
                .delay FILE_UPLOAD_DELAY
                .then ->
                    saveNextFile fileList

        saveNextFile saveList
            .catch (e)=>
                @model.item.description = oldDescription
                throw e

    _refreshByline: ->
        mod = @model.item?.modVersion?.mod
        if mod?.name?.length > 0
            @$bylineLink.attr 'href', Url.mod modSlug:mod.slug
            @$bylineLink.html mod.name

            @show @$byline
        else
            @hide @$byline

    _refreshDescription: ->
        if @model.item?.description?.length > 0
            @_descriptionController.model = @model.item.description
            @_descriptionController.resetToDefaultState()

    _refreshMultiblock: ->
        if @model.item?.multiblock?
            @_multiblockController.model = @model.item.multiblock
            @show @$multiblockSection
        else
            @hide @$multiblockSection

    _refreshRecipes: ->
        @_recipeControllers ?= []
        index = 0

        recipes = @model.findRecipes()
        if recipes?.length > 0
            @$recipesSectionTitle.html if recipes.length is 1 then 'Recipe' else 'Recipes'

            for recipe in @model.findRecipes()
                controller = @_recipeControllers[index]
                if not controller?
                    controller = new FullRecipeController imageLoader:@imageLoader, modPack:@modPack, model:recipe
                    @_recipeControllers.push controller
                    @$recipeContainer.append controller.$el
                    controller.render()
                else
                    controller.model = recipe
                index++

            @show @$recipesSection
        else
            @hide @$recipesSection

        while @_recipeControllers.length > index
            @_recipeControllers.pop().remove()

    _refreshSimilarItems: ->
        group = @model.item?.group
        if group? and group isnt Item.Group.Other
            @_similarItemsController.title = "Other #{group}"
            @_similarItemsController.model = @model.findSimilarItems()
        else
            @_similarItemsController.model = null

    _refreshUsedAsToolToMake: ->
        @_usedAsToolToMakeController.title = 'Used as Tool to Make'
        @_usedAsToolToMakeController.model = @model.findToolForRecipes()

    _refreshUsedToMake: ->
        @_usedToMakeController.title = 'Used to Make'
        @_usedToMakeController.model = @model.findComponentInItems()

    _refreshVideos: ->
        @_videoControllers ?= []
        index = 0

        videos = @model?.item?.videos or []
        if videos? and videos.length > 0
            @$videosSectionTitle.html if videos.length is 1 then 'Video' else 'Videos'

            for video in videos
                controller = @_videoControllers[index]
                if not controller?
                    controller = new VideoController model:video
                    @_videoControllers.push controller
                    controller.render()
                    @$videosContainer.append controller.$el
                else
                    controller.model = video
                index++

            @show @$videosSection
        else
            @hide @$videosSection

        while @_videoControllers.length > index
            @_videoControllers.pop().remove()

    _resolveItemSlug: ->
        return if @model.item?

        item = @modPack.findItem @_itemSlug, includeDisabled:true
        if item?
            if not ItemSlug.equal item.slug, @_itemSlug
                router.navigate Url.item(modSlug:item.slug.mod, itemSlug:item.slug.item), trigger:true
                return

            @model.item = item
            item.fetch()
            item.on Event.sync, => @refresh()
