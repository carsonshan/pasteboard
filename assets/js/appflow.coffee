### 
# Controls the flow of the application
# (what happens when)
###
appFlow = (pasteboard) ->
	# The different states that the app goes through
	states = {
		initializing: 0 
		insertingImage: 1
		editingImage: 2
		uploadingImage: 3
		generatingLink: 4
	}
	$pasteboard = $(pasteboard)
	$imageEditor = null
	$modalWindow = null

	setState = (state, stateData = {}) ->
		switch state
			# State 1: Application is initializing
			when states.initializing
				pasteboard.socketConnection.init()
				pasteboard.modalWindow.init()
				
				setState ++state
			
			# State 2: Waiting for user to insert an image
			when states.insertingImage
				# Set up drag and drop / copy and paste handlers
				pasteboard.dragAndDrop.init()
				pasteboard.copyAndPaste.init()

				# Show the splash screen
				$(".splash").show()

				$pasteboard.on "imageinserted", (e, eventData) ->
					$pasteboard.off "imageinserted"
					setState ++state, image: eventData.image

			# State 3: User is looking at / editing the image
			when states.editingImage
				unless stateData.backtracked
					# Start preuploading the image right away
					pasteboard.fileHandler.preuploadFile()
					# Hide things from the previous state
					pasteboard.dragAndDrop.hide()
					pasteboard.copyAndPaste.hide()
					$(".splash").hide()

					# Display the image editor
					pasteboard.imageEditor.init stateData.image

				# Triggered when clicking the delete button
				$imageEditor.on "cancel.stateevents", (e) ->
					$imageEditor.off ".stateevents"
					# Clear the preuploaded file
					pasteboard.fileHandler.clearFile()
					# Abort the (possibly) ongoing preupload
					pasteboard.fileHandler.abortPreupload()

					# Go back to the previous state
					pasteboard.imageEditor.hide () -> setState --state

				# Triggered when clicking the upload button
				$imageEditor.on "confirm.stateevents", (e) ->
					$imageEditor.off ".stateevents"
					# Upload the image
					pasteboard.imageEditor.uploadImage (upload) ->
						setState ++state, upload: upload

			# State 4: The image is uploading
			when states.uploadingImage
				progressHandler = null

				# Image upload still in progress
				if stateData.upload.inProgress
					pasteboard.modalWindow.show("upload-progress", 
							showCancel: true
							showConfirm: true
							confirmText: "Upload More"
						, (modal) ->
							alreadyLoaded = pasteboard.fileHandler.getCurrentUploadLoaded()

							progressHandler = (e) ->
								# When an image is still "preuploading" (i.e. the preupload
								# didn't finish before the user clicked the upload button),
								# begin the progress indicator from 0 by subtracting the already
								# loaded bytes
								if stateData.upload.preuploading
									percent = Math.floor(((e.loaded - alreadyLoaded) / (e.total - alreadyLoaded)) * 100)
								else
									percent = Math.floor((e.loaded / e.total) * 100)

								# Update the progress bar and number with the current %
								modal.find(".progress-bar")
									.css(
										width: "#{percent}%"
									)
								.end().find(".progress-number")
									.text(if ("" + percent).length < 2 then "0#{percent}" else percent)

								# The upload is complete (but still waiting for response from the server)
								if percent is 100 
									modal.find(".modal-window")
										.removeClass("default")
										.addClass("generating")
									
									# The upload can no longer be cancelled
									$modalWindow.off "cancel"

									if stateData.upload.preuploading
										# In the case of a continued preupload we need
										# to send another request to upload the preuploaded
										# image from the server to the cloud
										stateData.upload.xhr.addEventListener "load", () ->
											pasteboard.imageEditor.uploadImage (upload) ->
												setState ++state, $.extend(upload, jQueryXHR: true, modal: modal)
									else
										setState ++state,
											xhr: stateData.upload.xhr
											modal: modal

							stateData.upload.xhr.upload.addEventListener "progress", progressHandler
						)
				
				# Image is already uploaded, just waiting for
				# the upload between the server and the cloud
				# to finish	
				else
					pasteboard.modalWindow.show("upload-link", 
						showConfirm: true
						confirmText: "Upload more"
					, (modal) ->
						setState ++state, 
							xhr: stateData.upload.xhr,
							modal: modal
							preuploaded: true
					)

				# Triggered when an upload is cancelled
				$modalWindow.on "cancel.stateevents", () ->
					$modalWindow.off ".stateevents"
					# Only cancel the upload if it's not a preupload, else let it keep running in the background
					stateData.upload.xhr.abort() if stateData.upload.xhr and not stateData.upload.preuploading
					stateData.upload.xhr.upload.removeEventListener "progress", progressHandler
					
					# Backtrack to the image editing state
					pasteboard.modalWindow.hide()
					setState states.editingImage, backtracked: true

			# State 5: The image link is being generated
			when states.generatingLink
				# Image was already preuploaded when the upload
				# button was pressed
				if stateData.preuploaded
					stateData.xhr.success (data) ->
						stateData.modal.find(".modal-window")
							.removeClass("default generating")
							.addClass("done")

						stateData.modal.find(".image-link").val(data.url)
							
				else
					# Some animations to transition from displaying 
					# the upload bar to showing the image link
					showLink = (url) ->
						stateData.modal.find(".modal-window")
							.removeClass("generating")
							.addClass("done")

						setTimeout(() ->
							stateData.modal.find(".upload-bar")
								.hide()
							.end().find(".image-link")
								.show()
								.addClass("appear")

							stateData.modal.find(".cancel").transition( 
								opacity: 0
							, 500, () ->
								$(this).css "display", "none"
								stateData.modal.find(".confirm")
									.css("display", "block")
									.transition({
										opacity: 1
									}, 500)
							)

							setTimeout(() ->
								stateData.modal.find(".image-link").val(url)
							, 500)
						, 500)

					if stateData.jQueryXHR 
						stateData.xhr.success (data) ->
							showLink data.url
					else
						stateData.xhr.addEventListener "load", (e) ->
							json = {}
							try
								json = JSON.parse e.target.response
							catch e
								log e.target.response
							showLink(if json.url then json.url else "Something went wrong")
							
				# Go back to uploading another image
				$modalWindow.on "confirm.stateevents", () ->
					$modalWindow.off ".stateevents"
					pasteboard.modalWindow.hide()
					pasteboard.imageEditor.hide () -> setState states.insertingImage, backtracked: true
		
	self =
		# Starts the application flow
		start: () ->
			$imageEditor = $(pasteboard.imageEditor)
			$modalWindow = $(pasteboard.modalWindow)
			setState(0)

window.moduleLoader.addModule "appFlow", appFlow
