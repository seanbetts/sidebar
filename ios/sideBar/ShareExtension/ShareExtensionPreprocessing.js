var ShareExtensionPreprocessing = function() {};

ShareExtensionPreprocessing.prototype = {
    run: function(arguments) {
        arguments.completionFunction({
            url: document.location.href,
            baseURI: document.baseURI
        });
    }
};

var ExtensionPreprocessingJS = new ShareExtensionPreprocessing();
